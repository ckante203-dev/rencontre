import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ✅ NOUVEAU — n'accepte que les administrateurs.
// La clé "anon" publique n'est PAS un utilisateur : elle est refusée (401).
// Un utilisateur normal est refusé (403). Seul un compte présent dans la
// table `admins` passe.
async function requireAdmin(req: Request, supabase: any): Promise<Response | null> {
  const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!jwt) return jsonResponse({ error: 'Non autorisé' }, 401);

  const { data, error } = await supabase.auth.getUser(jwt);
  const email = data?.user?.email;
  if (error || !email) return jsonResponse({ error: 'Non autorisé' }, 401);

  const { data: adminRow } = await supabase
    .from('admins')
    .select('id')
    .eq('email', email)
    .maybeSingle();
  if (!adminRow) return jsonResponse({ error: 'Réservé aux administrateurs' }, 403);

  return null;
}

// ── Token OAuth2 mis en cache (même mécanique que les autres fonctions) ──
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

// ── Envoie à UN token, renvoie true/false ─────────────────────────
async function sendToOne(
  projectId: string,
  accessToken: string,
  fcmToken: string,
  title: string,
  body: string
): Promise<boolean> {
  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body },
            data: {
              title,
              body,
              type: 'admin_notification',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
              },
            },
          },
        }),
      }
    );
    return res.ok;
  } catch {
    return false;
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    // ✅ NOUVEAU — contrôle d'accès avant tout le reste
    const denied = await requireAdmin(req, supabase);
    if (denied) return denied;

    // Destinataires (un seul mode à la fois, par ordre de priorité) :
    //   token     : un appareil précis
    //   userIds   : une liste d'utilisateurs
    //   email     : UN utilisateur, retrouvé par son email
    //   audience  : 'all' (défaut) | 'online' (actif < 30 min) | 'premium'
    const { title, body, token, userIds, email, audience } = await req.json();

    if (!title || !body) {
      return jsonResponse({ error: 'title et body sont obligatoires' }, 400);
    }
    if (String(title).length > 100 || String(body).length > 500) {
      return jsonResponse({ error: 'title (100 max) ou body (500 max) trop long' }, 400);
    }

    const saRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!saRaw) {
      return jsonResponse({ error: 'FIREBASE_SERVICE_ACCOUNT non configuré' }, 500);
    }
    const sa = JSON.parse(saRaw);

    let tokens: string[] = [];

    if (token) {
      tokens = [String(token)];
    } else {
      let query = supabase
        .from('profiles')
        .select('fcm_token')
        .not('fcm_token', 'is', null)
        .neq('fcm_token', '');

      if (Array.isArray(userIds) && userIds.length > 0) {
        query = query.in('id', userIds);
      } else if (typeof email === 'string' && email.trim()) {
        query = query.eq('email', email.trim().toLowerCase());
      } else {
        query = query.eq('is_banned', false);
        if (audience === 'online') {
          query = query.gte('last_seen', new Date(Date.now() - 30 * 60 * 1000).toISOString());
        } else if (audience === 'premium') {
          query = query.eq('is_premium', true);
        } else if (audience !== undefined && audience !== null && audience !== 'all') {
          return jsonResponse({ error: 'audience invalide' }, 400);
        }
      }

      const { data, error } = await query;
      if (error) throw error;
      tokens = (data ?? []).map((p: any) => p.fcm_token).filter(Boolean);
    }

    tokens = [...new Set(tokens)];

    if (tokens.length === 0) {
      return jsonResponse({ success: true, sent: 0, message: 'Aucun token FCM trouvé' });
    }

    const accessToken = await getAccessToken(sa);

    // ✅ L'API FCM v1 n'a pas d'équivalent au multicast Legacy
    // (registration_ids en un seul appel) — on envoie en parallèle par
    // lots pour rester rapide sans surcharger le worker Deno.
    let totalSent = 0;
    let totalFailed = 0;
    const batchSize = 50;

    for (let i = 0; i < tokens.length; i += batchSize) {
      const batch = tokens.slice(i, i + batchSize);
      const results = await Promise.all(
        batch.map((t) => sendToOne(sa.project_id, accessToken, t, title, body))
      );
      totalSent += results.filter(Boolean).length;
      totalFailed += results.filter((r) => !r).length;
    }

    return jsonResponse({ success: true, sent: totalSent, failed: totalFailed, total: tokens.length });
  } catch (err: any) {
    console.error('❌ Error:', String(err));
    return jsonResponse({ error: err.message || 'Erreur interne' }, 500);
  }
});