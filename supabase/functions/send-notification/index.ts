import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Token mis en cache au niveau du module (persiste entre les requêtes du même worker)
let _accessToken: string | null = null;
let _tokenExpiry = 0;
let _cryptoKey: CryptoKey | null = null;

async function getCryptoKey(privateKeyPem: string): Promise<CryptoKey> {
  if (_cryptoKey) return _cryptoKey;
  const pem = privateKeyPem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\n/g, "");
  const der = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  _cryptoKey = await crypto.subtle.importKey(
    "pkcs8", der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  );
  return _cryptoKey;
}

function b64url(data: string | Uint8Array): string {
  const str = typeof data === "string" ? data : String.fromCharCode(...data);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (_accessToken && now < _tokenExpiry) return _accessToken;

  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));

  const signingInput = `${header}.${payload}`;
  const key = await getCryptoKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key,
    new TextEncoder().encode(signingInput)
  );

  const jwt = `${signingInput}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const data = await res.json();
  if (!data.access_token) throw new Error(`Token error: ${JSON.stringify(data)}`);
  
  _accessToken = data.access_token;
  _tokenExpiry = now + 3000;
  return _accessToken!;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*" } });
  }

  try {
    const body = await req.json();
    const record = body.record ?? body;
    const { conversation_id, sender_id, content, type } = record;

    if (!conversation_id || !sender_id) {
      return new Response("Missing fields", { status: 400 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!;
    
    const sa = JSON.parse(saRaw);
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Récupère conversation + token OAuth2 en parallèle
    const [{ data: conv }, accessToken] = await Promise.all([
      supabase.from("conversations")
        .select("user1_id, user2_id")
        .eq("id", conversation_id)
        .single(),
      getAccessToken(sa),
    ]);

    if (!conv) {
      console.log("Conversation not found:", conversation_id);
      return new Response("conv not found", { status: 404 });
    }

    const recipientId = conv.user1_id === sender_id ? conv.user2_id : conv.user1_id;

    const [{ data: recipient }, { data: sender }] = await Promise.all([
      supabase.from("profiles").select("fcm_token").eq("id", recipientId).single(),
      supabase.from("profiles").select("name").eq("id", sender_id).single(),
    ]);

    if (!recipient?.fcm_token) {
      console.log("No FCM token for recipient:", recipientId);
      return new Response("no fcm token", { status: 200 });
    }

    const senderName = sender?.name ?? "Quelqu'un";
    const notifBody = type === "text"
      ? (content?.length > 100 ? content.substring(0, 97) + "..." : content ?? "")
      : type === "image" ? "📷 Photo"
      : type === "audio" ? "🎤 Vocal"
      : "Nouveau message";

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: recipient.fcm_token,
            notification: { title: senderName, body: notifBody },
            data: {
              type: "message",
              conversationId: conversation_id,
              senderId: sender_id,
              senderName,
            },
            android: {
              priority: "high",
              notification: {
                sound: "default",
                channel_id: "messages",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
            },
          },
        }),
      }
    );

    const result = await fcmRes.json();
    console.log("✅ FCM result:", JSON.stringify(result));

    return new Response(JSON.stringify({ success: true, result }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("❌ Error:", String(err));
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});