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


// ── Accès réservé à la base de données (fonctions SQL notify_new_*) ──
// Elles appellent cette fonction avec la clé secrète du projet
// (sb_secret_…). Sans cette vérification, n'importe qui possédant la clé
// publique de l'app pouvait envoyer de fausses notifications.
function internalKeys(): string[] {
  const keys: string[] = [];
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const v = JSON.parse(raw);
      if (typeof v === "string") keys.push(v);
      else if (Array.isArray(v)) keys.push(...v.filter((s) => typeof s === "string"));
      else if (v && typeof v === "object") {
        keys.push(...Object.values(v).filter((s): s is string => typeof s === "string"));
      }
    } catch {
      keys.push(raw);
    }
  }
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) keys.push(legacy);
  return keys.filter((k) => k.length > 0);
}

function sameString(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

function isInternalCaller(req: Request): boolean {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return false;
  const token = auth.slice(7).trim();
  return internalKeys().some((k) => sameString(token, k));
}

serve(async (req) => {
  if (!isInternalCaller(req)) {
    return new Response("Unauthorized", { status: 401 });
  }

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
      // select("*") : les colonnes de préférences peuvent manquer sur
      // d'anciens profils, une liste explicite ferait échouer la requête.
      supabase.from("profiles").select("*").eq("id", recipientId).single(),
      supabase.from("profiles").select("name").eq("id", sender_id).single(),
    ]);

    if (!recipient?.fcm_token) {
      console.log("No FCM token for recipient:", recipientId);
      return new Response("no fcm token", { status: 200 });
    }

    // Réglage « Notifications > Messages » désactivé par le destinataire
    if (recipient.notif_messages === false) {
      return new Response("notif messages désactivées", { status: 200 });
    }
    // Conversation mise en sourdine par le destinataire (menu ⋮ du chat).
    // Table absente (script 000014 pas appliqué) → on notifie normalement.
    const { data: sourdine } = await supabase
      .from("conversation_sourdines")
      .select("user_id")
      .eq("user_id", recipientId)
      .eq("conversation_id", conversation_id)
      .maybeSingle();
    if (sourdine) {
      return new Response("conversation en sourdine", { status: 200 });
    }

    // Réglage « Son des notifications » désactivé → canal silencieux
    const silencieux = recipient.notif_son === false;

    const senderName = sender?.name ?? "Quelqu'un";
    // Image : l'app met le genre dans le texte (« 🎨 Sticker », « 🎞️ GIF »,
    // « 🎬 Vidéo », « 🔞 Photo »…). Une photo sensible reste discrète.
    const texte: string = content ?? "";
    const notifBody = type === "text"
      ? (texte.length > 100 ? texte.substring(0, 97) + "..." : texte)
      : type === "image"
        ? (texte.startsWith("🔞") ? "📷 Photo"
          : texte.startsWith("🎨") || texte.startsWith("🎞") || texte.startsWith("🎬")
            ? texte
            : "📷 Photo")
      : type === "audio" ? "🎤 Vocal"
      : type === "snap" ? "📸 Photo éphémère"
      : type === "location" ? "📍 Position"
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
                ...(silencieux ? {} : { sound: "default" }),
                channel_id: silencieux ? "messages_silencieux" : "messages",
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