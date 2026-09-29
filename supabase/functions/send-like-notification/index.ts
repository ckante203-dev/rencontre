// supabase/functions/send-like-notification/index.ts
// Appelée par l'app avec le JWT utilisateur (verify_jwt activé).

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

// ── Handler principal ─────────────────────────────────────────────────────
// Appelée par l'app (like_controller.dart) avec le JWT utilisateur et
// { from_user_id, to_user_id, is_match }.
// - from_user_id est pris du JWT (le body doit correspondre, sinon 403)
// - le like doit exister réellement en base
// - is_match est recalculé côté serveur (like réciproque)
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const user = await getAuthUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const uid = user.id;

    const payload = await req.json().catch(() => null);
    if (!payload || typeof payload !== "object") return json({ error: "invalid body" }, 400);
    const { from_user_id, to_user_id } = payload as Record<string, unknown>;

    if (from_user_id !== undefined && from_user_id !== null && from_user_id !== uid) {
      return json({ error: "forbidden" }, 403);
    }
    if (typeof to_user_id !== "string" || !UUID_RE.test(to_user_id) || to_user_id === uid) {
      return json({ error: "Missing fields" }, 400);
    }

    // Le like doit exister (uid → to_user_id) ; is_match = like réciproque
    const [likeRes, reverseRes, fromRes, toRes] = await Promise.all([
      admin.from("likes").select("from_user_id")
        .eq("from_user_id", uid).eq("to_user_id", to_user_id).limit(1),
      admin.from("likes").select("from_user_id")
        .eq("from_user_id", to_user_id).eq("to_user_id", uid).limit(1),
      admin.from("profiles").select("name, photo_url, is_suspended")
        .eq("id", uid).maybeSingle(),
      admin.from("profiles").select("fcm_token, blocked_users")
        .eq("id", to_user_id).maybeSingle(),
    ]);

    for (const r of [likeRes, reverseRes, fromRes, toRes]) {
      if (r.error) throw new Error(`DB error: ${r.error.message}`);
    }

    if (!likeRes.data || likeRes.data.length === 0) {
      return json({ error: "like not found" }, 403);
    }
    const isMatch = (reverseRes.data?.length ?? 0) > 0;

    const fromProfile = fromRes.data;
    const toProfile = toRes.data;

    if (!fromProfile) {
      console.log("from_profile not found:", uid);
      return json({ error: "from_profile not found" }, 404);
    }
    if (fromProfile.is_suspended === true) {
      console.log("Sender suspended, skip:", uid);
      return json({ success: true, skipped: "sender_suspended" });
    }
    const blocked: string[] = Array.isArray(toProfile?.blocked_users) ? toProfile!.blocked_users : [];
    if (blocked.includes(uid)) {
      console.log("Recipient blocked sender, skip:", to_user_id);
      return json({ success: true, skipped: "blocked" });
    }
    if (!toProfile?.fcm_token) {
      console.log("No FCM token for:", to_user_id);
      return json({ success: true, skipped: "no_fcm_token" });
    }

    // ── Contenu de la notif (inchangé) ──────────────────────────────────
    const name = fromProfile.name ?? "Quelqu'un";
    const title = isMatch ? "💘 Nouveau Match !" : `❤️ ${name} t'a liké !`;
    const body = isMatch
      ? `Toi et ${name} vous vous êtes likés mutuellement !`
      : `${name} a liké ton profil. Like en retour !`;
    const channelId = isMatch ? "matches" : "messages";

    const data = {
      type: isMatch ? "match" : "like",
      from_user_id: uid,
      from_user_name: name,
      from_user_photo: fromProfile.photo_url ?? "",
    };

    const result = await sendFCM(toProfile.fcm_token, title, body, data, channelId);

    if (!result.ok) {
      if (result.invalidToken) {
        await clearInvalidToken(admin, to_user_id, toProfile.fcm_token);
        console.log("Invalid FCM token cleared for:", to_user_id);
        return json({ success: false, skipped: "invalid_token" });
      }
      console.error("❌ FCM error:", result.status, result.error);
      return json({ error: "fcm_failed", status: result.status }, 502);
    }

    console.log(`✅ FCM ${data.type} sent to ${to_user_id}`);
    return json({ success: true, is_match: isMatch });
  } catch (err) {
    console.error("❌ Error:", String(err));
    return json({ error: "internal error" }, 500);
  }
});
