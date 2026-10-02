// supabase/functions/revenuecat-webhook/index.ts
//
// ⚠️ DOIT être déployée avec --no-verify-jwt :
//     supabase functions deploy revenuecat-webhook --no-verify-jwt
// RevenueCat n'envoie pas de JWT Supabase : l'authentification se fait via
// le header Authorization configuré dans le dashboard RevenueCat
// ("Bearer <REVENUECAT_WEBHOOK_SECRET>").

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const REVENUECAT_WEBHOOK_SECRET = Deno.env.get('REVENUECAT_WEBHOOK_SECRET') ?? '';
const PREMIUM_ENTITLEMENT_ID = 'zamu_premium';

// Boosts (produits Google Play à usage unique) → durée en minutes.
const BOOST_MINUTES: Record<string, number> = {
  boost_1h: 60,
  boost_2h: 120,
  boost_24h: 24 * 60,
};

/** « boost_1h » ou « boost_1h:xxx » → minutes, sinon null. */
function boostMinutes(productId: unknown): number | null {
  if (typeof productId !== 'string') return null;
  return BOOST_MINUTES[productId.split(':')[0]] ?? null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Comparaison en temps constant (hash des deux valeurs puis XOR octet par octet)
async function safeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(a)),
    crypto.subtle.digest('SHA-256', enc.encode(b)),
  ]);
  const x = new Uint8Array(ha);
  const y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

/** Ids candidats valides (UUID Supabase), dans l'ordre, sans doublon. Les ids anonymes ($RCAnonymousID:...) sont ignorés. */
function uuidCandidates(...lists: unknown[]): string[] {
  const out: string[] = [];
  for (const l of lists) {
    const arr = Array.isArray(l) ? l : [l];
    for (const v of arr) {
      if (typeof v === 'string' && UUID_RE.test(v) && !out.includes(v.toLowerCase())) {
        out.push(v.toLowerCase());
      }
    }
  }
  return out;
}

/** Met à jour is_premium sur le premier candidat qui correspond à un profil. Retourne l'id mis à jour ou null. */
async function setPremium(candidates: string[], value: boolean): Promise<string | null> {
  for (const id of candidates) {
    const { data, error } = await supabase
      .from('profiles')
      .update({ is_premium: value })
      .eq('id', id)
      .select('id');
    if (error) throw new Error(`DB update failed: ${error.message}`);
    if (data && data.length > 0) return id;
  }
  return null;
}

serve(async (req) => {
  if (!REVENUECAT_WEBHOOK_SECRET) {
    console.error('REVENUECAT_WEBHOOK_SECRET non configuré : webhook refusé');
    return new Response('Server misconfigured', { status: 500 });
  }

  // ✅ Vérifie que l'appel vient bien de RevenueCat
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!(await safeEqual(authHeader, `Bearer ${REVENUECAT_WEBHOOK_SECRET}`))) {
    return new Response('Unauthorized', { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const event = body?.event;
  if (!event) {
    return new Response('No event', { status: 400 });
  }

  const type: string = event.type ?? '';
  const environment: string = event.environment ?? 'UNKNOWN';
  const entitlementIds: string[] = Array.isArray(event.entitlement_ids)
    ? event.entitlement_ids
    : (event.entitlement_id ? [event.entitlement_id] : []);

  console.log(`RevenueCat event ${type} (${environment}) id=${event.id ?? '?'}`);

  try {
    // ── TRANSFER : l'abonnement passe d'un compte à un autre ──────────────
    if (type === 'TRANSFER') {
      // Certains TRANSFER n'ont pas d'entitlement_ids ; s'ils en ont, on
      // n'agit que pour l'entitlement premium.
      if (entitlementIds.length > 0 && !entitlementIds.includes(PREMIUM_ENTITLEMENT_ID)) {
        return new Response('Ignored (not premium entitlement)', { status: 200 });
      }
      const from = uuidCandidates(event.transferred_from);
      const to = uuidCandidates(event.transferred_to);

      const fromId = from.length ? await setPremium(from, false) : null;
      const toId = to.length ? await setPremium(to, true) : null;

      console.log(`✅ TRANSFER from=${fromId ?? 'none'} → to=${toId ?? 'none'}`);
      if (!toId) {
        console.warn('TRANSFER : aucun profil trouvé pour transferred_to', JSON.stringify(event.transferred_to));
      }
      return new Response('OK', { status: 200 });
    }

    // ── BOOST : achat unique, accordé par le serveur ──────────────────────
    const minutes = boostMinutes(event.product_id);
    if (minutes !== null) {
      if (type !== 'NON_RENEWING_PURCHASE' && type !== 'INITIAL_PURCHASE') {
        return new Response('OK', { status: 200 });
      }
      const ids = uuidCandidates(event.app_user_id, event.original_app_user_id, event.aliases);
      const transaction = String(event.transaction_id ?? event.id ?? '');
      if (ids.length === 0 || !transaction) {
        console.warn(`Boost ignoré (user=${event.app_user_id}, transaction=${transaction})`);
        return new Response('Ignored (boost without user/transaction)', { status: 200 });
      }
      for (const id of ids) {
        const { data, error } = await supabase.rpc('appliquer_boost', {
          p_user: id,
          p_transaction: transaction,
          p_produit: String(event.product_id),
          p_minutes: minutes,
        });
        if (error) throw new Error(`appliquer_boost: ${error.message}`);
        if (data) {
          console.log(`⚡ Boost ${event.product_id} → ${id} jusqu'à ${data} (${environment})`);
          return new Response('OK', { status: 200 });
        }
      }
      console.warn(`Boost : aucun profil pour ${ids.join(', ')}`);
      return new Response('Ignored (profile not found)', { status: 200 });
    }

    if (!entitlementIds.includes(PREMIUM_ENTITLEMENT_ID)) {
      return new Response('Ignored (not premium entitlement)', { status: 200 });
    }

    let newStatus: boolean | null = null;
    switch (type) {
      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'UNCANCELLATION':
      case 'PRODUCT_CHANGE':
        newStatus = true;
        break;
      case 'EXPIRATION':
        newStatus = false;
        break;
      // CANCELLATION : l'utilisateur garde l'accès jusqu'à la fin de la
      // période payée → on ne change rien ici, EXPIRATION s'en chargera.
      default:
        break;
    }

    if (newStatus === null) {
      return new Response('OK', { status: 200 });
    }

    const candidates = uuidCandidates(event.app_user_id, event.original_app_user_id, event.aliases);
    if (candidates.length === 0) {
      // Id anonyme / non-UUID : on répond 200 pour éviter les retries infinis
      console.warn(`Aucun app_user_id UUID exploitable (app_user_id=${event.app_user_id}) — ignoré`);
      return new Response('Ignored (no valid user id)', { status: 200 });
    }

    const updatedId = await setPremium(candidates, newStatus);
    if (!updatedId) {
      console.warn(`Aucun profil trouvé pour ${candidates.join(', ')} — ignoré`);
      return new Response('Ignored (profile not found)', { status: 200 });
    }

    console.log(`✅ ${updatedId} → is_premium = ${newStatus} (${type}, ${environment})`);
    return new Response('OK', { status: 200 });
  } catch (e) {
    console.error('Supabase update error:', String(e));
    return new Response('DB update failed', { status: 500 });
  }
});
