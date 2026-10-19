// supabase/functions/connexion-pseudo/index.ts
// Connexion avec @pseudo + mot de passe, SANS jamais renvoyer l'e-mail.
// Avant, l'app lisait profiles.email par pseudo avant d'être connectée : la
// lecture anonyme de la table laissait n'importe qui aspirer tous les
// e-mails (fermée par SQL 097).
// Appelée sans compte → déployer avec --no-verify-jwt.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const PSEUDO_RE = /^[a-z0-9_.]{3,20}$/;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erreur: "methode" }, 405);

  let pseudo = "", motDePasse = "";
  try {
    const body = await req.json();
    pseudo = String(body.pseudo ?? "").trim().toLowerCase().replace(/^@+/, "");
    motDePasse = String(body.mot_de_passe ?? "");
  } catch {
    return json({ erreur: "requete" }, 400);
  }
  // Même réponse pour « pseudo inconnu » et « mauvais mot de passe » :
  // on ne révèle pas si un pseudo existe.
  const refus = () => json({ erreur: "identifiants" }, 401);
  if (!PSEUDO_RE.test(pseudo) || motDePasse.length < 6 || motDePasse.length > 200) {
    return refus();
  }

  const { data: profil } = await admin
    .from("profiles")
    .select("email")
    .eq("username", pseudo)
    .maybeSingle();
  const email = (profil?.email as string | undefined)?.trim();
  if (!email) return refus();

  // Connexion « normale » côté serveur (mêmes limites anti-abus que l'app)
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password: motDePasse,
  });
  if (error || !data.session) {
    const msg = (error?.message ?? "").toLowerCase();
    if (msg.includes("email not confirmed")) {
      return json({ erreur: "email_non_confirme" }, 401);
    }
    if (msg.includes("rate")) return json({ erreur: "trop_de_tentatives" }, 429);
    return refus();
  }
  return json({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
  });
});
