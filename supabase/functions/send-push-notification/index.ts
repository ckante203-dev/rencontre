// supabase/functions/send-push-notification/index.ts
// Appelée par Database Webhook (messages INSERT, header x-webhook-secret).
// À déployer avec --no-verify-jwt : l'authentification (secret webhook OU JWT
// utilisateur réel) est faite dans le code.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? SUPABASE_SERVICE_ROLE_KEY;

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-webhook-secret",
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ── Authentification ─────────────────────────────────────────────────────
// La gateway (verify_jwt) accepte aussi la clé anon : on vérifie donc ici
// qu'il s'agit bien d'un VRAI utilisateur connecté.
async function getAuthUser(req: Request): Promise<{ id: string; email?: string } | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const m = authHeader.match(/^Bearer\s+(\S+)$/i);
  if (!m) return null;
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await userClient.auth.getUser(m[1]);
  if (error || !data?.user?.id) return null;
  return data.user;
}

// ── Webhook (Database Webhook) : secret partagé en header x-webhook-secret ──
async function safeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const x = new Uint8Array(ha);
  const y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

/** true = secret valide ; false = header absent ; "invalid" = header présent mais refusé. */
async function checkWebhookSecret(req: Request): Promise<boolean | "invalid"> {
  const provided = req.headers.get("x-webhook-secret");
  if (provided === null) return false;
  const expected = Deno.env.get("WEBHOOK_SECRET") ?? "";
  if (!expected) {
    console.error("WEBHOOK_SECRET non configuré : appel webhook refusé");
    return "invalid";
  }
  return (await safeEqual(provided, expected)) ? true : "invalid";
}

// ── FCM v1 (Service Account) — token OAuth2 mis en cache par worker ──────
// (helpers dupliqués volontairement dans chaque fonction pour un déploiement simple)
let _sa: any = null;
let _accessToken: string | null = null;
let _tokenExpiry = 0;
let _cryptoKey: CryptoKey | null = null;

function getServiceAccount(): any {
  if (_sa) return _sa;
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT manquant");
  _sa = JSON.parse(raw);
  return _sa;
}

async function getCryptoKey(privateKeyPem: string): Promise<CryptoKey> {
  if (_cryptoKey) return _cryptoKey;
  const pem = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\\n|\n|\r/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  _cryptoKey = await crypto.subtle.importKey(
    "pkcs8", der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"],
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

  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const sigInput = `${header}.${payload}`;
  const key = await getCryptoKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(sigInput),
  );
  const jwt = `${sigInput}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(`OAuth token error (${res.status}): ${JSON.stringify(data)}`);
  }
  _accessToken = data.access_token;
  _tokenExpiry = now + 3000;
  return _accessToken!;
}

/** FCM n'accepte que des valeurs string dans `data`. */
function stringData(obj: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === null || v === undefined) out[k] = "";
    else out[k] = typeof v === "string" ? v : typeof v === "object" ? JSON.stringify(v) : String(v);
  }
  return out;
}

type FcmResult = { ok: true } | { ok: false; invalidToken: boolean; status: number; error: string };

async function sendFCM(
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
  channelId: string,
): Promise<FcmResult> {
  const sa = getServiceAccount();
  const accessToken = await getAccessToken(sa);
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: { "Authorization": `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: { title, body },
          data: stringData(data),
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
    },
  );
  if (res.ok) {
    await res.body?.cancel();
    return { ok: true };
  }

  const text = await res.text();
  let status = "";
  let errorCode = "";
  let message = "";
  try {
    const j = JSON.parse(text);
    status = j?.error?.status ?? "";
    message = j?.error?.message ?? "";
    for (const d of j?.error?.details ?? []) {
      if (d?.errorCode) errorCode = d.errorCode;
    }
  } catch (_) { /* corps non JSON */ }

  if (res.status === 401) {
    // Token OAuth expiré/révoqué : on force un renouvellement au prochain envoi
    _accessToken = null;
    _tokenExpiry = 0;
  }

  const invalidToken =
    errorCode === "UNREGISTERED" ||
    status === "NOT_FOUND" || errorCode === "NOT_FOUND" ||
    ((status === "INVALID_ARGUMENT" || errorCode === "INVALID_ARGUMENT") &&
      /token/i.test(message));

  return { ok: false, invalidToken, status: res.status, error: text.slice(0, 500) };
}

/** Met fcm_token à null si le token FCM n'est plus valide (seulement s'il n'a pas changé entre-temps). */
async function clearInvalidToken(admin: any, userId: string | null, token: string) {
  try {
    let q = admin.from("profiles").update({ fcm_token: null }).eq("fcm_token", token);
    if (userId) q = q.eq("id", userId);
    const { error } = await q;
    if (error) console.error("clearInvalidToken error:", error.message);
  } catch (e) {
    console.error("clearInvalidToken exception:", String(e));
  }
}

// ── Notification "nouveau message" ────────────────────────────────────────
// Le message est TOUJOURS relu en base à partir de son id (on ne fait pas
// confiance au contenu du body). Si l'appel vient d'un utilisateur (JWT),
// il doit être l'expéditeur du message.
async function notifyNewMessage(messageId: string, jwtUid: string | null): Promise<Response> {
  const { data: msg, error: msgErr } = await admin
    .from("messages")
    .select("id, conversation_id, sender_id, type, content")
    .eq("id", messageId)
    .maybeSingle();
  if (msgErr) throw new Error(`DB error: ${msgErr.message}`);
  if (!msg) {
    console.log("Message not found:", messageId);
    return json({ error: "message not found" }, 404);
  }

  const senderId: string = msg.sender_id;
  if (jwtUid !== null && senderId !== jwtUid) {
    return json({ error: "forbidden" }, 403);
  }

  const { data: conv, error: convErr } = await admin
    .from("conversations")
    .select("user1_id, user2_id")
    .eq("id", msg.conversation_id)
    .maybeSingle();
  if (convErr) throw new Error(`DB error: ${convErr.message}`);
  if (!conv) {
    console.log("Conversation not found:", msg.conversation_id);
    return json({ error: "conv not found" }, 404);
  }
  if (senderId !== conv.user1_id && senderId !== conv.user2_id) {
    console.warn("Sender is not a participant:", senderId, msg.conversation_id);
    return json({ error: "forbidden" }, 403);
  }

  const recipientId: string = conv.user1_id === senderId ? conv.user2_id : conv.user1_id;

  const [{ data: recipient, error: rErr }, { data: sender, error: sErr }] = await Promise.all([
    admin.from("profiles").select("fcm_token, blocked_users").eq("id", recipientId).maybeSingle(),
    admin.from("profiles").select("name, is_suspended").eq("id", senderId).maybeSingle(),
  ]);
  if (rErr) throw new Error(`DB error: ${rErr.message}`);
  if (sErr) throw new Error(`DB error: ${sErr.message}`);

  if (sender?.is_suspended === true) {
    return json({ success: true, skipped: "sender_suspended" });
  }
  const blocked: string[] = Array.isArray(recipient?.blocked_users) ? recipient!.blocked_users : [];
  if (blocked.includes(senderId)) {
    return json({ success: true, skipped: "blocked" });
  }
  if (!recipient?.fcm_token) {
    console.log("No FCM token for recipient:", recipientId);
    return json({ success: true, skipped: "no_fcm_token" });
  }

  const senderName: string = sender?.name ?? "Quelqu'un";
  const notifBody = messageLabel(msg.type, msg.content);

  const result = await sendFCM(
    recipient.fcm_token,
    senderName,
    notifBody,
    {
      type: "message",
      conversationId: msg.conversation_id,
      senderId,
      senderName,
    },
    "messages",
  );

  if (!result.ok) {
    if (result.invalidToken) {
      await clearInvalidToken(admin, recipientId, recipient.fcm_token);
      console.log("Invalid FCM token cleared for:", recipientId);
      return json({ success: false, skipped: "invalid_token" });
    }
    console.error("❌ FCM error:", result.status, result.error);
    return json({ error: "fcm_failed", status: result.status }, 502);
  }

  console.log("✅ FCM message notification sent to", recipientId);
  return json({ success: true });
}

/** Extrait l'id du message depuis un payload de Database Webhook ({ record }) ou d'un appel direct. */
function extractMessageId(payload: any): string | null {
  const record = payload?.record ?? payload?.new ?? payload;
  const id = record?.id ?? payload?.message_id;
  return typeof id === "string" && id.length > 0 ? id : (typeof id === "number" ? String(id) : null);
}

function messageLabel(type: string, content: string | null): string {
  return type === "text"
    ? ((content?.length ?? 0) > 100 ? content!.substring(0, 97) + "..." : content ?? "")
    : type === "image" ? "📷 Photo"
    : type === "audio" ? "🎤 Vocal"
    : type === "video" ? "🎥 Vidéo"
    : "Nouveau message";
}

// ── Handler principal ─────────────────────────────────────────────────────
// Deux modes d'appel :
//  1. Database Webhook (INSERT sur messages) : payload { type, table, schema,
//     record, old_record } + header x-webhook-secret obligatoire (= secret
//     WEBHOOK_SECRET). Le message est relu en base à partir de record.id.
//  2. App (JWT utilisateur) : { record: { id } } ou { message_id } ;
//     l'appelant doit être l'expéditeur et participant de la conversation.
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const webhook = await checkWebhookSecret(req);
    if (webhook === "invalid") return json({ error: "unauthorized" }, 401);

    const payload = await req.json().catch(() => null);
    if (!payload || typeof payload !== "object") return json({ error: "invalid body" }, 400);

    if (webhook === true) {
      if (payload.table && payload.table !== "messages") {
        return json({ error: "unexpected table" }, 400);
      }
      if (payload.type && payload.type !== "INSERT") {
        return json({ success: true, skipped: "not_insert" });
      }
      const messageId = extractMessageId(payload);
      if (!messageId) return json({ error: "Missing fields" }, 400);
      return await notifyNewMessage(messageId, null);
    }

    const user = await getAuthUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);

    const messageId = extractMessageId(payload);
    if (!messageId) return json({ error: "Missing fields" }, 400);
    return await notifyNewMessage(messageId, user.id);
  } catch (err) {
    console.error("Error:", String(err));
    return json({ error: "internal error" }, 500);
  }
});
