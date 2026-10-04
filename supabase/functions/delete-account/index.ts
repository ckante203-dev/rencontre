// supabase/functions/delete-account/index.ts
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

// ── Storage ───────────────────────────────────────────────────────────────
// Conventions de chemins utilisées par l'app (lib/) :
//   avatars        : "<uid>/photo.ext", "avatars/<uid>/profile.jpg"
//   profile-photos : "<uid>/<ts>.ext"
//   snaps          : "snaps/<uid>/...", "photos/<uid>/...", "audio/<uid>/..."
//   stories        : "stories/<uid>/..."
// albums : album privé, chemins "<uid>/<ts>.jpg"
const BUCKETS = ["avatars", "profile-photos", "snaps", "stories", "albums"];
const SUBFOLDERS = ["avatars", "snaps", "photos", "audio", "videos", "stories"];

async function listAllFiles(bucket: string, prefix: string, depth = 0): Promise<string[]> {
  if (depth > 5) return [];
  const files: string[] = [];
  const LIMIT = 100;
  for (let offset = 0; ; offset += LIMIT) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, {
      limit: LIMIT,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw new Error(`list ${bucket}/${prefix}: ${error.message}`);
    if (!data || data.length === 0) break;
    for (const item of data) {
      const path = `${prefix}/${item.name}`;
      if (item.id === null) {
        // Dossier
        files.push(...await listAllFiles(bucket, path, depth + 1));
      } else {
        files.push(path);
      }
    }
    if (data.length < LIMIT) break;
  }
  return files;
}

async function deleteUserFiles(uid: string): Promise<string[]> {
  const errors: string[] = [];
  const prefixes = [uid, ...SUBFOLDERS.map((s) => `${s}/${uid}`)];
  for (const bucket of BUCKETS) {
    for (const prefix of prefixes) {
      try {
        const files = await listAllFiles(bucket, prefix);
        for (let i = 0; i < files.length; i += 100) {
          const { error } = await admin.storage.from(bucket).remove(files.slice(i, i + 100));
          if (error) throw new Error(`remove ${bucket}: ${error.message}`);
        }
        if (files.length) console.log(`storage ${bucket}/${prefix}: ${files.length} fichier(s) supprimé(s)`);
      } catch (e) {
        const msg = String(e);
        // Bucket inexistant : pas bloquant
        if (/not found/i.test(msg)) continue;
        console.error("storage cleanup error:", msg);
        errors.push(msg);
      }
    }
  }
  return errors;
}

// ── Lignes dépendantes ────────────────────────────────────────────────────
// Chaque suppression est isolée : une table/colonne absente (42P01 / 42703)
// n'interrompt pas les autres.
async function safeDelete(table: string, column: string, value: string | string[]): Promise<string | null> {
  try {
    let q = admin.from(table).delete();
    q = Array.isArray(value) ? q.in(column, value) : q.eq(column, value);
    const { error } = await q;
    if (!error) return null;
    if (["42P01", "42703", "PGRST204", "PGRST205"].includes(error.code ?? "")) {
      console.log(`skip ${table}.${column}: ${error.message}`);
      return null;
    }
    console.error(`delete ${table}.${column} error:`, error.message);
    return `${table}.${column}: ${error.message}`;
  } catch (e) {
    console.error(`delete ${table}.${column} exception:`, String(e));
    return `${table}.${column}: ${String(e)}`;
  }
}

async function selectIds(table: string, column: string, value: string, idCol = "id"): Promise<string[]> {
  try {
    const { data, error } = await admin.from(table).select(idCol).eq(column, value);
    if (error) return [];
    return (data ?? []).map((r: any) => r[idCol]).filter(Boolean);
  } catch (_) {
    return [];
  }
}

async function deleteUserRows(uid: string): Promise<string[]> {
  const errs: (string | null)[] = [];

  // Conversations où l'utilisateur est participant (+ leurs messages / typing)
  const convIds = [
    ...await selectIds("conversations", "user1_id", uid),
    ...await selectIds("conversations", "user2_id", uid),
  ];
  // Stories de l'utilisateur (+ leurs commentaires)
  const storyIds = await selectIds("stories", "user_id", uid);

  for (let i = 0; i < convIds.length; i += 100) {
    const chunk = convIds.slice(i, i + 100);
    errs.push(await safeDelete("typing_status", "conversation_id", chunk));
    errs.push(await safeDelete("messages", "conversation_id", chunk));
  }
  for (let i = 0; i < storyIds.length; i += 100) {
    errs.push(await safeDelete("story_comments", "story_id", storyIds.slice(i, i + 100)));
  }

  errs.push(
    await safeDelete("likes", "from_user_id", uid),
    await safeDelete("likes", "to_user_id", uid),
    await safeDelete("follows", "follower_id", uid),
    await safeDelete("follows", "followed_id", uid),
    await safeDelete("profile_views", "viewer_id", uid),
    await safeDelete("profile_views", "viewed_id", uid),
    await safeDelete("notifications", "user_id", uid),
    await safeDelete("notifications", "actor_id", uid),
    await safeDelete("story_comments", "user_id", uid),
    await safeDelete("stories", "user_id", uid),
    await safeDelete("typing_status", "user_id", uid),
    await safeDelete("messages", "sender_id", uid),
    await safeDelete("conversations", "user1_id", uid),
    await safeDelete("conversations", "user2_id", uid),
    await safeDelete("matches", "user1_id", uid),
    await safeDelete("matches", "user2_id", uid),
    await safeDelete("reports", "reporter_id", uid),
    // album_photos / album_acces / favoris : supprimés en cascade avec le
    // profil ; favoris_alertes n'a pas de clé étrangère.
    await safeDelete("favoris_alertes", "user_id", uid),
    await safeDelete("favoris_alertes", "favori_id", uid),
  );
  return errs.filter((e): e is string => e !== null);
}

// Vrai si l'utilisateur connecté est un administrateur (table admins).
async function isAdmin(user: { email?: string }): Promise<boolean> {
  if (!user.email) return false;
  const { data } = await admin
    .from("admins")
    .select("email")
    .eq("email", user.email)
    .maybeSingle();
  return data != null;
}

// ── Handler principal ─────────────────────────────────────────────────────
// • App (controleur_profil.dart) : JWT de l'utilisateur, sans body →
//   supprime SON compte.
// • Panneau admin : JWT d'un admin + body { "user_id": "<uuid>" } →
//   supprime ce compte-là (refusé si l'appelant n'est pas dans admins).
// Supprime les fichiers, les données puis le compte.
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const user = await getAuthUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);

    let cible: string | undefined;
    try {
      const body = await req.json();
      if (body && typeof body.user_id === "string") cible = body.user_id;
    } catch (_) {
      // pas de body : suppression de son propre compte
    }

    let uid = user.id;
    if (cible && cible !== user.id) {
      if (!UUID_RE.test(cible)) return json({ error: "user_id invalide" }, 400);
      if (!(await isAdmin(user))) return json({ error: "forbidden" }, 403);
      // Un admin ne peut pas supprimer un autre admin par ce biais
      const { data: cibleUser } = await admin.auth.admin.getUserById(cible);
      if (cibleUser?.user && (await isAdmin(cibleUser.user))) {
        return json({ error: "impossible de supprimer un admin" }, 403);
      }
      uid = cible;
      console.log(`Suppression admin du compte ${cible} par ${user.email}`);
    }

    // 1. Fichiers Storage (non bloquant : on journalise les erreurs)
    const storageErrors = await deleteUserFiles(uid);

    // 2. Lignes dépendantes
    const rowErrors = await deleteUserRows(uid);

    // 3. Profil
    const { error: profileError } = await admin.from("profiles").delete().eq("id", uid);
    if (profileError) {
      console.error("profile delete error:", profileError.message, rowErrors);
      return json({ error: "profile delete failed", details: [profileError.message, ...rowErrors] }, 500);
    }

    // 4. Compte d'authentification
    const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
    if (deleteError) {
      console.error("auth delete error:", deleteError.message);
      return json({ error: "auth delete failed" }, 500);
    }

    if (storageErrors.length || rowErrors.length) {
      console.warn(`Compte ${uid} supprimé avec avertissements`, { storageErrors, rowErrors });
    } else {
      console.log(`Compte ${uid} supprimé`);
    }
    return new Response("OK", { status: 200, headers: cors });
  } catch (err) {
    console.error("❌ Error:", String(err));
    return json({ error: "internal error" }, 500);
  }
});
