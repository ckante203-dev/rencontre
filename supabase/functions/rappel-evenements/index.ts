// supabase/functions/rappel-evenements/index.ts
//
// Notifications des événements (appelée par pg_cron toutes les heures,
// job `rappel-evenements`). La liste « qui reçoit quoi » est calculée en
// SQL par notifs_evenements_a_envoyer() (migration 035) : rappel la
// veille et 2 h avant, « des personnes que tu as likées y vont »,
// « nouvel événement près de toi ». Chaque envoi est noté dans
// evenement_notifs : jamais deux fois la même notification.
//
// Déploiement : supabase functions deploy rappel-evenements --no-verify-jwt
// Secret      : PURGE_SECRET (le même que purge-expired, Vault purge_secret)
// Test à blanc : POST avec ?apercu=1 → renvoie la liste sans rien envoyer.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PURGE_SECRET = Deno.env.get("PURGE_SECRET") ?? "";
const PAR_LOT = 20; // envois FCM en parallèle

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

// ── Token OAuth2 FCM (même code que dynamic-processor) ─────────────
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
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const sigInput = `${header}.${payload}`;
  const key = await getCryptoKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(sigInput),
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
  _tokenExpiry = now + 3000;
  return _accessToken!;
}

type NotifEvenement = {
  user_id: string;
  fcm_token: string;
  evenement_id: string;
  type: string;
  titre: string;
  corps: string;
};

// "ok" | "jeton_mort" (appli désinstallée) | "erreur"
async function envoyer(n: NotifEvenement, sa: any): Promise<string> {
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
          token: n.fcm_token,
          notification: { title: n.titre, body: n.corps },
          data: { type: "evenement", evenement_id: n.evenement_id, rappel: n.type },
          android: {
            priority: n.type === "2h" ? "high" : "normal",
            notification: {
              sound: "default",
              channel_id: "smart",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        },
      }),
    },
  );
  if (res.ok) return "ok";
  const err = await res.json().catch(() => ({}));
  const code = JSON.stringify(err);
  if (res.status === 404 || code.includes("UNREGISTERED")) return "jeton_mort";
  console.error(`FCM ${n.user_id}:`, code);
  return "erreur";
}

serve(async (req) => {
  if (!PURGE_SECRET) {
    return new Response("PURGE_SECRET non configuré", { status: 500 });
  }
  const given = req.headers.get("x-purge-secret") ?? "";
  if (!timingSafeEqual(given, PURGE_SECRET)) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { data, error } = await admin.rpc("notifs_evenements_a_envoyer");
  if (error) {
    console.error("notifs_evenements_a_envoyer:", error.message);
    return new Response(error.message, { status: 500 });
  }
  const liste = (data ?? []) as NotifEvenement[];

  if (new URL(req.url).searchParams.get("apercu") === "1") {
    return new Response(
      JSON.stringify(liste.map(({ fcm_token: _, ...n }) => n)),
      { headers: { "Content-Type": "application/json" } },
    );
  }
  if (liste.length === 0) {
    return new Response(JSON.stringify({ candidats: 0 }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
  const notees: { evenement_id: string; user_id: string; type: string }[] = [];
  const morts = new Set<string>();
  let envoyes = 0, erreurs = 0;

  for (let i = 0; i < liste.length; i += PAR_LOT) {
    const lot = liste.slice(i, i + PAR_LOT);
    const res = await Promise.all(
      lot.map((n) => envoyer(n, sa).catch(() => "erreur")),
    );
    res.forEach((statut, j) => {
      const n = lot[j];
      if (statut === "erreur") { erreurs++; return; } // réessayé à l'heure suivante
      if (statut === "ok") envoyes++;
      else morts.add(n.user_id);
      notees.push({ evenement_id: n.evenement_id, user_id: n.user_id, type: n.type });
    });
  }

  for (let i = 0; i < notees.length; i += 500) {
    await admin.from("evenement_notifs")
      .upsert(notees.slice(i, i + 500), { ignoreDuplicates: true });
  }
  if (morts.size) {
    await admin.from("profiles").update({ fcm_token: null }).in("id", [...morts]);
  }

  const bilan = { candidats: liste.length, envoyes, jetons_morts: morts.size, erreurs };
  console.log("✅ rappel-evenements:", JSON.stringify(bilan));
  return new Response(JSON.stringify(bilan), {
    headers: { "Content-Type": "application/json" },
  });
});
