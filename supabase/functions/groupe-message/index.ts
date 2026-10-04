// supabase/functions/groupe-message/index.ts
//
// Notification push d'un message de groupe. Appelée par le trigger SQL
// apres_message_groupe (migration 036) avec la clé secrète du projet :
// toute autre requête est refusée. Les destinataires sont choisis en SQL
// (destinataires_message_groupe : pas l'auteur, pas en sourdine, au plus
// une notification toutes les 5 minutes par personne et par groupe).
//
// Déploiement : supabase functions deploy groupe-message

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

async function envoyer(
  token: string, titre: string, corps: string,
  data: Record<string, string>, sa: any,
): Promise<string> {
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
          token,
          notification: { title: titre, body: corps },
          data,
          android: {
            priority: "high",
            notification: {
              sound: "default",
              channel_id: "messages",
              tag: `groupe_${data.groupe_id}`, // une seule notif par groupe
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        },
      }),
    },
  );
  if (res.ok) return "ok";
  const err = JSON.stringify(await res.json().catch(() => ({})));
  if (res.status === 404 || err.includes("UNREGISTERED")) return "jeton_mort";
  console.error("FCM groupe:", err);
  return "erreur";
}

// ── Accès réservé à la base de données (trigger SQL) ──────────────
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
  try {
    const { message_id } = await req.json();
    if (!message_id) return new Response("Missing message_id", { status: 400 });

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: msg } = await admin.from("groupe_messages")
      .select("id, groupe_id, sender_id, type, contenu, groupes(nom), profiles(name)")
      .eq("id", message_id).maybeSingle();
    if (!msg || msg.type === "systeme") return new Response("ignoré");

    const { data: dest, error } = await admin.rpc(
      "destinataires_message_groupe", { p_message: message_id });
    if (error) throw new Error(error.message);
    const liste = (dest ?? []) as { user_id: string; fcm_token: string }[];
    if (!liste.length) return new Response(JSON.stringify({ envoyes: 0 }));

    const groupe = (msg as any).groupes?.nom ?? "Groupe";
    const auteur = (msg as any).profiles?.name ?? "Quelqu'un";
    const apercu = msg.type === "image" ? "📷 Photo"
      : msg.type === "giphy" ? "GIF"
      : String(msg.contenu ?? "").slice(0, 120);
    const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
    const data = { type: "groupe", groupe_id: String(msg.groupe_id) };

    const morts: string[] = [];
    let envoyes = 0;
    for (let i = 0; i < liste.length; i += 20) {
      const lot = liste.slice(i, i + 20);
      const res = await Promise.all(lot.map((d) =>
        envoyer(d.fcm_token, `👥 ${groupe}`, `${auteur} : ${apercu}`, data, sa)
          .catch(() => "erreur")));
      res.forEach((r, j) => {
        if (r === "ok") envoyes++;
        else if (r === "jeton_mort") morts.push(lot[j].user_id);
      });
    }
    if (morts.length) {
      await admin.from("profiles").update({ fcm_token: null }).in("id", morts);
    }
    return new Response(JSON.stringify({ envoyes, jetons_morts: morts.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("groupe-message:", String(e));
    return new Response(String(e), { status: 500 });
  }
});
