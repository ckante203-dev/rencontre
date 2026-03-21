// supabase/functions/send-like-notification/index.ts
// Même pattern que tes fonctions existantes (FCM v1 + Service Account)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Token OAuth2 mis en cache ─────────────────────────────────────
let _accessToken: string | null = null;
let _tokenExpiry = 0;
let _cryptoKey: CryptoKey | null = null;

async function getCryptoKey(privateKeyPem: string): Promise<CryptoKey> {
  if (_cryptoKey) return _cryptoKey;
  const pem = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\n/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  _cryptoKey = await crypto.subtle.importKey(
    "pkcs8", der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  );
  return _cryptoKey;
}

function b64url(data: string | Uint8Array): string {
  const str = typeof data === "string"
    ? data
    : String.fromCharCode(...data);
  return btoa(str)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (_accessToken && now < _tokenExpiry) return _accessToken;

  const header  = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));

  const sigInput = `${header}.${payload}`;
  const key = await getCryptoKey(sa.private_key);
  const sig  = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key,
    new TextEncoder().encode(sigInput)
  );

  const jwt = `${sigInput}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const data = await res.json();
  if (!data.access_token) throw new Error(`Token error: ${JSON.stringify(data)}`);

  _accessToken = data.access_token;
  _tokenExpiry  = now + 3000;
  return _accessToken!;
}

// ── Envoyer une notif FCM v1 ──────────────────────────────────────
async function sendFCM(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
  channelId: string,
  sa: any
) {
  const accessToken = await getAccessToken(sa);
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              sound: "default",
              channel_id: channelId,
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        },
      }),
    }
  );
  return res.json();
}

// ── Handler principal ─────────────────────────────────────────────
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: { "Access-Control-Allow-Origin": "*" },
    });
  }

  try {
    const { from_user_id, to_user_id, is_match } = await req.json();

    if (!from_user_id || !to_user_id) {
      return new Response("Missing fields", { status: 400 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ✅ Même secret que tes autres fonctions
    const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);

    // Récupérer les deux profils en parallèle
    const [{ data: fromProfile }, { data: toProfile }] = await Promise.all([
      supabase.from("profiles")
        .select("name, photo_url")
        .eq("id", from_user_id)
        .single(),
      supabase.from("profiles")
        .select("fcm_token")
        .eq("id", to_user_id)
        .single(),
    ]);

    if (!fromProfile) {
      console.log("from_profile not found:", from_user_id);
      return new Response("from_profile not found", { status: 404 });
    }

    if (!toProfile?.fcm_token) {
      console.log("No FCM token for:", to_user_id);
      return new Response("no fcm token", { status: 200 });
    }

    // ── Contenu de la notif ───────────────────────────────────────
    const title = is_match
      ? "💘 Nouveau Match !"
      : `❤️ ${fromProfile.name} t'a liké !`;

    const body = is_match
      ? `Toi et ${fromProfile.name} vous vous êtes likés mutuellement !`
      : `${fromProfile.name} a liké ton profil. Like en retour !`;

    const channelId = is_match ? "matches" : "messages";

    const data: Record<string, string> = {
      type: is_match ? "match" : "like",
      from_user_id,
      from_user_name: fromProfile.name,
      from_user_photo: fromProfile.photo_url ?? "",
    };

    // ── Envoi FCM ─────────────────────────────────────────────────
    const result = await sendFCM(
      toProfile.fcm_token,
      title,
      body,
      data,
      channelId,
      sa
    );

    console.log("✅ FCM like/match result:", JSON.stringify(result));

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