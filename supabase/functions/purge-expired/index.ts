// supabase/functions/purge-expired/index.ts
//
// Purge automatique (appelée par pg_cron toutes les 15 min) :
//   1. stories expirées (expires_at dépassé) → fichier du bucket `stories`
//      + commentaires + ligne supprimés ;
//   2. snaps ouverts dont le délai est écoulé (expires_at) → seule la
//      photo est supprimée, le message reste comme trace « Snap ouvert » ;
//      messages lus depuis plus de 24h (read_at), traces de snaps de plus
//      de 24h et anciens messages « mode éphémère » (disappears_at) →
//      fichier du bucket `snaps` + ligne supprimés ;
//   3. fichiers en attente dans `storage_a_supprimer` (lignes supprimées
//      en SQL, dont le fichier restait dans le Storage).
//
// Le Storage ne peut pas être vidé en SQL : c'est pour ça que cette
// fonction existe (API Storage), le cron ne fait que l'appeler.
//
// Déploiement : supabase functions deploy purge-expired --no-verify-jwt
// Secret      : supabase secrets set PURGE_SECRET=<valeur>  (même valeur
//               que le secret `purge_secret` du Vault utilisé par le cron)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PURGE_SECRET = Deno.env.get("PURGE_SECRET") ?? "";

const MESSAGE_TTL_MS = 24 * 60 * 60 * 1000;
const BATCH = 200;
const TIME_BUDGET_MS = 50_000;

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

// URL publique → chemin dans le bucket (null si le fichier n'est pas dans ce bucket)
function pathFromUrl(url: string | null, bucket: string): string | null {
  if (!url) return null;
  const marker = `/storage/v1/object/public/${bucket}/`;
  const i = url.indexOf(marker);
  if (i === -1) return null;
  const raw = url.substring(i + marker.length).split("?")[0];
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

// Supprime des fichiers ; ceux qui échouent sont remis dans la file
// d'attente pour un prochain passage (jamais perdus).
async function removeFiles(bucket: string, paths: string[]): Promise<number> {
  let removed = 0;
  for (let i = 0; i < paths.length; i += 100) {
    const chunk = paths.slice(i, i + 100);
    const { error } = await admin.storage.from(bucket).remove(chunk);
    if (error) {
      console.error(`storage remove ${bucket}:`, error.message);
      await admin
        .from("storage_a_supprimer")
        .upsert(chunk.map((path) => ({ bucket, path })), { ignoreDuplicates: true });
    } else {
      removed += chunk.length;
    }
  }
  return removed;
}

async function purgeStories(deadline: number) {
  let rows = 0;
  let files = 0;
  while (Date.now() < deadline) {
    const { data, error } = await admin
      .from("stories")
      .select("id, media_url")
      .lt("expires_at", new Date().toISOString())
      .limit(BATCH);
    if (error) throw new Error(`stories select: ${error.message}`);
    if (!data || data.length === 0) break;

    const ids = data.map((s: any) => s.id);
    const paths = data
      .map((s: any) => pathFromUrl(s.media_url, "stories"))
      .filter((p: string | null): p is string => !!p);
    files += await removeFiles("stories", paths);

    // Commentaires (au cas où la clé étrangère n'est pas en cascade)
    const { error: cErr } = await admin.from("story_comments").delete().in("story_id", ids);
    if (cErr) console.error("story_comments delete:", cErr.message);

    const { error: dErr } = await admin.from("stories").delete().in("id", ids);
    if (dErr) throw new Error(`stories delete: ${dErr.message}`);
    rows += ids.length;
    if (data.length < BATCH) break;
  }
  return { rows, files };
}

async function purgeMessages(deadline: number) {
  let rows = 0;
  let files = 0;
  const maintenant = () => new Date().toISOString();

  // 1. Snaps ouverts dont le délai est écoulé : on supprime la PHOTO mais
  //    on garde le message (trace « Snap ouvert » dans la discussion,
  //    comme Snapchat). Il part ensuite avec la règle des 24 h ci-dessous.
  while (Date.now() < deadline) {
    const { data, error } = await admin
      .from("messages")
      .select("id, media_url")
      .lt("expires_at", maintenant())
      .not("media_url", "is", null)
      .limit(BATCH);
    if (error) throw new Error(`snaps select: ${error.message}`);
    if (!data || data.length === 0) break;
    const ids = data.map((m: any) => m.id);
    const paths = data
      .map((m: any) => pathFromUrl(m.media_url, "snaps"))
      .filter((p: string | null): p is string => !!p);
    files += await removeFiles("snaps", paths);
    const { error: uErr } = await admin.from("messages")
      .update({ media_url: null }).in("id", ids);
    if (uErr) throw new Error(`snaps update: ${uErr.message}`);
    if (data.length < BATCH) break;
  }

  // 2. Messages supprimés pour de bon : lus depuis plus de 24 h, anciens
  //    messages « mode éphémère » (disappears_at), traces de snaps expirés
  //    depuis plus de 24 h.
  while (Date.now() < deadline) {
    const limitDate = new Date(Date.now() - MESSAGE_TTL_MS).toISOString();
    const { data, error } = await admin
      .from("messages")
      .select("id, media_url")
      .or(
        `read_at.lt.${limitDate},expires_at.lt.${limitDate},` +
          `disappears_at.lt.${maintenant()}`,
      )
      .limit(BATCH);
    if (error) throw new Error(`messages select: ${error.message}`);
    if (!data || data.length === 0) break;

    const ids = data.map((m: any) => m.id);
    const paths = data
      .map((m: any) => pathFromUrl(m.media_url, "snaps"))
      .filter((p: string | null): p is string => !!p);
    files += await removeFiles("snaps", paths);

    const { error: dErr } = await admin.from("messages").delete().in("id", ids);
    if (dErr) throw new Error(`messages delete: ${dErr.message}`);
    rows += ids.length;
    if (data.length < BATCH) break;
  }
  return { rows, files };
}

async function purgeQueue(deadline: number) {
  let files = 0;
  while (Date.now() < deadline) {
    const { data, error } = await admin
      .from("storage_a_supprimer")
      .select("bucket, path")
      .limit(500);
    if (error) {
      // Table absente : rien en attente
      console.error("storage_a_supprimer select:", error.message);
      break;
    }
    if (!data || data.length === 0) break;

    const byBucket = new Map<string, string[]>();
    for (const r of data as any[]) {
      byBucket.set(r.bucket, [...(byBucket.get(r.bucket) ?? []), r.path]);
    }
    let progressed = false;
    for (const [bucket, paths] of byBucket) {
      const { error: rErr } = await admin.storage.from(bucket).remove(paths);
      if (rErr) {
        console.error(`queue remove ${bucket}:`, rErr.message);
        continue;
      }
      await admin.from("storage_a_supprimer").delete().eq("bucket", bucket).in("path", paths);
      files += paths.length;
      progressed = true;
    }
    if (!progressed || data.length < 500) break;
  }
  return { files };
}

serve(async (req) => {
  if (!PURGE_SECRET) {
    return new Response("PURGE_SECRET non configuré", { status: 500 });
  }
  const given = req.headers.get("x-purge-secret") ?? "";
  if (!timingSafeEqual(given, PURGE_SECRET)) {
    return new Response("Unauthorized", { status: 401 });
  }

  const deadline = Date.now() + TIME_BUDGET_MS;
  // Chaque étape est indépendante : un échec n'empêche pas les autres.
  const errors: string[] = [];
  const step = async <T>(name: string, fn: () => Promise<T>): Promise<T | null> => {
    try {
      return await fn();
    } catch (err) {
      console.error(`❌ purge-expired ${name}:`, String(err));
      errors.push(`${name}: ${String(err)}`);
      return null;
    }
  };

  const stories = await step("stories", () => purgeStories(deadline));
  const messages = await step("messages", () => purgeMessages(deadline));
  const queue = await step("queue", () => purgeQueue(deadline));
  const result = { stories, messages, queue, errors };
  console.log("✅ purge-expired:", JSON.stringify(result));
  return new Response(JSON.stringify(result), {
    status: errors.length ? 500 : 200,
    headers: { "Content-Type": "application/json" },
  });
});
