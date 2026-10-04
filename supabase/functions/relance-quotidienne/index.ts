// supabase/functions/relance-quotidienne/index.ts
//
// Notifications de relance (appelée par pg_cron chaque jour à 19 h UTC,
// job `relance-quotidienne`) : la liste « qui reçoit quoi » est calculée en
// SQL par relances_du_jour() (migration 029), cette fonction ne fait
// qu'envoyer les pushes FCM et noter la date d'envoi (derniere_relance).
//
// Déploiement : supabase functions deploy relance-quotidienne --no-verify-jwt
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

type Relance = {
  user_id: string;
  fcm_token: string;
  titre: string;
  corps: string;
  type: string;
  filtre: string | null;
};

// "ok" | "jeton_mort" (appli désinstallée) | "erreur"
async function envoyer(r: Relance, sa: any): Promise<string> {
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
          token: r.fcm_token,
          notification: { title: r.titre, body: r.corps },
          data: { type: r.type, filtre: r.filtre ?? "" },
          android: {
            priority: "normal",
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
  console.error(`FCM ${r.user_id}:`, code);
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

  const { data, error } = await admin.rpc("relances_du_jour");
  if (error) {
    console.error("relances_du_jour:", error.message);
    return new Response(error.message, { status: 500 });
  }
  const relances = (data ?? []) as Relance[];

  if (new URL(req.url).searchParams.get("apercu") === "1") {
    return new Response(
      JSON.stringify(relances.map(({ fcm_token: _, ...r }) => r)),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
  const envoyes: string[] = [];
  const morts: string[] = [];
  let erreurs = 0;

  for (let i = 0; i < relances.length; i += PAR_LOT) {
    const lot = relances.slice(i, i + PAR_LOT);
    const res = await Promise.all(
      lot.map((r) => envoyer(r, sa).catch(() => "erreur")),
    );
    res.forEach((statut, j) => {
      if (statut === "ok") envoyes.push(lot[j].user_id);
      else if (statut === "jeton_mort") morts.push(lot[j].user_id);
      else erreurs++;
    });
  }

  const maintenant = new Date().toISOString();
  if (envoyes.length) {
    await admin.from("profiles")
      .update({ derniere_relance: maintenant })
      .in("id", envoyes);
  }
  // Appli désinstallée : on oublie le jeton (l'app le renvoie à sa
  // prochaine ouverture si elle est réinstallée).
  if (morts.length) {
    await admin.from("profiles").update({ fcm_token: null }).in("id", morts);
  }

  const bilan = {
    candidats: relances.length,
    envoyes: envoyes.length,
    jetons_morts: morts.length,
    erreurs,
  };
  console.log("✅ relance-quotidienne:", JSON.stringify(bilan));
  return new Response(JSON.stringify(bilan), {
    headers: { "Content-Type": "application/json" },
  });
});
