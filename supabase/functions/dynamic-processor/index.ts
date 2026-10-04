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
  sa: any,
  silencieux = false
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
              ...(silencieux ? {} : { sound: "default" }),
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

// ── Contenu de la notif selon le type d'événement ──────────────────
// ✅ Distingue proprement follow / like / match, chacun avec son titre,
// son texte et son channel Android — au lieu d'afficher systématiquement
// "t'a liké" même pour un nouvel abonné.
type EventType =
  | "follow" | "like" | "match"
  // ⭐ Favoris (trigger SQL sur profiles, 20261002000021_favoris.sql)
  | "favori_en_ligne" | "favori_proche" | "favori_ville" | "favori_story";

function buildNotificationContent(
  eventType: EventType,
  fromName: string,
  distanceKm?: number
): { title: string; body: string; channelId: string } {
  switch (eventType) {
    case "favori_en_ligne":
      return {
        title: `⭐ ${fromName} est en ligne`,
        body: `Ton favori ${fromName} vient de se connecter. Dis-lui bonjour !`,
        channelId: "likes",
      };
    case "favori_proche":
      return {
        title: `⭐ ${fromName} est près de toi`,
        body: distanceKm != null && distanceKm < 1
          ? `Ton favori est à moins d'1 km de toi`
          : `Ton favori est à environ ${Math.round(distanceKm ?? 0)} km de toi`,
        channelId: "likes",
      };
    case "favori_story":
      return {
        title: `⭐ ${fromName} a publié une story`,
        body: `Va vite la voir avant qu'elle disparaisse 👀`,
        channelId: "likes",
      };
    case "favori_ville":
      return {
        title: `⭐ ${fromName} est dans ta ville`,
        body: `Ton favori ${fromName} vient d'arriver près de chez toi`,
        channelId: "likes",
      };
    case "match":
      return {
        title: "💘 Nouveau Match !",
        body: `Toi et ${fromName} vous vous êtes likés mutuellement !`,
        channelId: "matches",
      };
    case "follow":
      return {
        title: `👤 ${fromName} s'est abonné à toi !`,
        body: `${fromName} suit maintenant ton profil.`,
        channelId: "follows",
      };
    case "like":
    default:
      return {
        title: `❤️ ${fromName} t'a liké !`,
        body: `${fromName} a liké ton profil. Like en retour !`,
        channelId: "likes",
      };
  }
}

// ── Handler principal ─────────────────────────────────────────────

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
    return new Response("ok", {
      headers: { "Access-Control-Allow-Origin": "*" },
    });
  }

  try {
    const payload = await req.json();
    const { from_user_id, to_user_id, is_match } = payload;
    // ✅ "type" est optionnel pour rester compatible avec les appels
    // existants qui n'envoient que { from_user_id, to_user_id, is_match }.
    // Si absent, on déduit le type depuis is_match (comportement historique).
    const explicitType = payload.type as EventType | undefined;
    const eventType: EventType =
      explicitType ?? (is_match ? "match" : "like");
    const estFavori = eventType.startsWith("favori");

    if (!from_user_id || !to_user_id) {
      return new Response("Missing fields", { status: 400 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);

    // Récupérer les deux profils en parallèle
    const [{ data: fromProfile }, { data: toProfile }] = await Promise.all([
      supabase.from("profiles")
        .select("name, photo_url")
        .eq("id", from_user_id)
        .single(),
      // select("*") : les colonnes de préférences peuvent manquer
      supabase.from("profiles")
        .select("*")
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

    // Réglage « Alertes de mes favoris » désactivé
    if (estFavori && toProfile.notif_favoris === false) {
      return new Response("favoris coupés", { status: 200 });
    }

    let { title, body, channelId } = buildNotificationContent(
      eventType,
      fromProfile.name,
      typeof payload.distance_km === "number" ? payload.distance_km : undefined
    );

    let data: Record<string, string> = {
      type: eventType,
      from_user_id,
      from_user_name: fromProfile.name,
      from_user_photo: fromProfile.photo_url ?? "",
    };

    // 💸 Like reçu par un compte GRATUIT : on ne dévoile pas qui (c'est
    // l'avantage Premium « Vois qui t'a liké »). Le tap ouvre l'onglet ❤️
    // (photos floutées). Un match reste nominatif (like réciproque).
    if (eventType === "like" && toProfile.is_premium !== true) {
      title = "❤️ Quelqu'un t'a liké !";
      body = "Découvre qui t'a liké 👀";
      data = { type: "like_anonyme" };
    }

    // ── Envoi FCM ─────────────────────────────────────────────────
    // Réglage « Son des notifications » désactivé → canal silencieux
    const silencieux = toProfile.notif_son === false;
    const result = await sendFCM(
      toProfile.fcm_token,
      title,
      body,
      data,
      silencieux ? `${channelId}_silencieux` : channelId,
      sa,
      silencieux
    );

    console.log(`✅ FCM ${eventType} result:`, JSON.stringify(result));

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