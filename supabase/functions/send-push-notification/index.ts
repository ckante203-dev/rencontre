import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

async function getAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encode = (obj: any) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");

  const signingInput = `${encode(header)}.${encode(payload)}`;

  const pemKey = serviceAccount.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");

  const binaryKey = Uint8Array.from(atob(pemKey), c => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  const jwt = `${signingInput}.${btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "")}`;

  const tokenRes = await fetch(serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenRes.json();
  return tokenData.access_token;
}

async function sendFCM(fcmToken: string, title: string, body: string, data: Record<string, string>, serviceAccount: any) {
  const accessToken = await getAccessToken(serviceAccount);
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: { sound: "default", channel_id: "messages", click_action: "FLUTTER_NOTIFICATION_CLICK" },
          },
        },
      }),
    }
  );
  return res.json();
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*" } });
  }

  try {
    const body = await req.json();
    console.log("Webhook payload:", JSON.stringify(body));

    // Le webhook Supabase envoie : { type, table, schema, record, old_record }
    // record = la nouvelle ligne insérée
    const record = body.record ?? body.new ?? body;
    const { conversation_id, sender_id, content, type } = record;

    if (!conversation_id || !sender_id) {
      return new Response("Missing fields", { status: 400 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const serviceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);

    // Trouver le destinataire
    const { data: conv } = await supabase
      .from("conversations")
      .select("user1_id, user2_id")
      .eq("id", conversation_id)
      .single();

    if (!conv) return new Response("conv not found", { status: 404 });

    const recipientId = conv.user1_id === sender_id ? conv.user2_id : conv.user1_id;

    // Token FCM + nom expéditeur en parallèle
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
      : type === "video" ? "🎥 Vidéo"
      : "Nouveau message";

    const result = await sendFCM(
      recipient.fcm_token,
      senderName,
      notifBody,
      { type: "message", conversationId: conversation_id, senderId: sender_id, senderName },
      serviceAccount
    );

    console.log("FCM result:", JSON.stringify(result));
    return new Response(JSON.stringify({ success: true, result }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("Error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});