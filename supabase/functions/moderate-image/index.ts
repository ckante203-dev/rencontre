// supabase/functions/moderate-image/index.ts
// Appelée par l'app avec le JWT utilisateur (verify_jwt activé).
//
// Statuts renvoyés :
//   approved  → publiée
//   unchecked → publiée, mais NON analysée (quota Sightengine dépassé,
//               service indisponible, vidéo) : à contrôler par l'admin
//   pending   → douteuse : cachée jusqu'à validation par l'admin
//   rejected  → explicite : refusée, fichier supprimé

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
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

type Status = "approved" | "unchecked" | "pending" | "rejected";

const MAX_GALLERY = 4; // = ControleurProfil.maxPhotos

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

function decide(n: any): Status {
  const explicit = Math.max(n?.sexual_activity ?? 0, n?.sexual_display ?? 0);
  if (explicit >= 0.85) return "rejected";
  if (explicit >= 0.45 || (n?.erotica ?? 0) >= 0.75) return "pending";
  return "approved";
}

async function scan(url: string): Promise<Status> {
  try {
    const q = new URLSearchParams({
      url,
      models: "nudity-2.1",
      api_user: Deno.env.get("SIGHTENGINE_USER") ?? "",
      api_secret: Deno.env.get("SIGHTENGINE_SECRET") ?? "",
    });
    const r = await fetch(`https://api.sightengine.com/1.0/check.json?${q}`);
    const j = await r.json();
    if (j.status !== "success") {
      // Quota dépassé, clé invalide, image illisible… : on ne bloque pas
      // l'utilisateur, la photo est publiée et marquée « à contrôler ».
      console.error("sightengine:", JSON.stringify(j.error ?? j));
      return "unchecked";
    }
    return decide(j.nudity);
  } catch (e) {
    console.error("sightengine fetch:", String(e));
    return "unchecked";
  }
}

// ── Validation de l'URL : fichier public de NOTRE Storage, dans le dossier de l'utilisateur ──
// Formats acceptés : <prefix><bucket>/<uid>/...   (ex. profile-photos/<uid>/x.jpg, avatars/<uid>/photo.jpg)
//                    <prefix><bucket>/<sous-dossier>/<uid>/...   (ex. avatars/avatars/<uid>/profile.jpg)
const PUBLIC_PREFIX = `${SUPABASE_URL.replace(/\/+$/, "")}/storage/v1/object/public/`;
const KNOWN_SUBFOLDERS = ["avatars", "photos", "stories"];

// Renvoie { bucket, path } si l'URL est un fichier de l'utilisateur, sinon null.
function ownStorageObject(
  url: unknown,
  uid: string,
  buckets: string[],
): { bucket: string; path: string } | null {
  if (typeof url !== "string" || !url.startsWith(PUBLIC_PREFIX)) return null;
  let rest = url.slice(PUBLIC_PREFIX.length).split(/[?#]/)[0];
  try {
    rest = decodeURIComponent(rest);
  } catch (_) {
    return null;
  }
  const segs = rest.split("/");
  if (segs.some((s) => s === "" || s === "." || s === ".." || s.includes("\\"))) return null;
  const [bucket, ...path] = segs;
  if (!buckets.includes(bucket)) return null;
  // path = [<uid>, fichier...]  ou  [<sous-dossier>, <uid>, fichier...]
  const ok = (path.length >= 2 && path[0] === uid) ||
    (path.length >= 3 && KNOWN_SUBFOLDERS.includes(path[0]) && path[1] === uid);
  return ok ? { bucket, path: path.join("/") } : null;
}

async function removeFile(obj: { bucket: string; path: string } | null) {
  if (!obj) return;
  const { error } = await admin.storage.from(obj.bucket).remove([obj.path]);
  if (error) console.error("remove file:", error.message);
}

function asList(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x) => typeof x === "string") : [];
}

// ── Handler principal ─────────────────────────────────────────────────────
// Appel app (JWT) :
//   { kind: "profile", url }  photo principale (avatars)
//   { kind: "gallery", url }  photo de la galerie (profile-photos)
//   { kind: "story",   id }   story déjà insérée (on lit la ligne en base)
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const user = await getAuthUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const uid = user.id;

    const payload = await req.json().catch(() => null);
    if (!payload || typeof payload !== "object") return json({ error: "invalid body" }, 400);
    const { kind, url, id } = payload as Record<string, unknown>;
    let status: Status;

    if (kind === "profile") {
      const obj = ownStorageObject(url, uid, ["avatars", "profile-photos"]);
      if (!obj) return json({ error: "forbidden" }, 403);
      const photoUrl = url as string;
      status = await scan(photoUrl);

      const update = status === "approved" || status === "unchecked"
        ? { photo_url: photoUrl, pending_photo_url: null, photo_status: status }
        : status === "pending"
        ? { pending_photo_url: photoUrl, photo_status: "pending" }
        : { pending_photo_url: null, photo_status: "rejected" };
      const { error } = await admin.from("profiles").update(update).eq("id", uid);
      if (error) throw new Error(`DB error: ${error.message}`);
      if (status === "rejected") await removeFile(obj);
    } else if (kind === "gallery") {
      const obj = ownStorageObject(url, uid, ["profile-photos"]);
      if (!obj) return json({ error: "forbidden" }, 403);
      const photoUrl = url as string;

      const { data: prof, error: pErr } = await admin.from("profiles")
        .select("photo_urls, pending_photo_urls").eq("id", uid).maybeSingle();
      if (pErr) throw new Error(`DB error: ${pErr.message}`);
      const photos = asList(prof?.photo_urls);
      const pendings = asList(prof?.pending_photo_urls);
      if (photos.length + pendings.length >= MAX_GALLERY) {
        await removeFile(obj);
        return json({ error: "gallery full" }, 409);
      }

      status = await scan(photoUrl);
      if (status === "approved" || status === "unchecked") {
        if (!photos.includes(photoUrl)) photos.push(photoUrl);
        const { error } = await admin.from("profiles")
          .update({ photo_urls: photos }).eq("id", uid);
        if (error) throw new Error(`DB error: ${error.message}`);
      } else if (status === "pending") {
        if (!pendings.includes(photoUrl)) pendings.push(photoUrl);
        const { error } = await admin.from("profiles")
          .update({ pending_photo_urls: pendings }).eq("id", uid);
        if (error) throw new Error(`DB error: ${error.message}`);
      } else {
        await removeFile(obj);
      }
    } else if (kind === "story") {
      if ((typeof id !== "string" && typeof id !== "number") || id === "") {
        return json({ error: "Missing fields" }, 400);
      }
      const { data: story, error: stErr } = await admin.from("stories")
        .select("id, media_url, is_video").eq("id", id).eq("user_id", uid).maybeSingle();
      if (stErr) throw new Error(`DB error: ${stErr.message}`);
      if (!story) return json({ error: "forbidden" }, 403);
      if (!story.media_url) return json({ error: "no media" }, 400);

      // Vidéos : pas d'analyse (bien plus coûteuse) → publiées, à contrôler.
      status = story.is_video === true ? "unchecked" : await scan(story.media_url);

      if (status === "rejected") {
        const { error } = await admin.from("stories").delete().eq("id", story.id);
        if (error) throw new Error(`DB error: ${error.message}`);
        await removeFile(ownStorageObject(story.media_url, uid, ["stories"]));
      } else {
        const { error } = await admin.from("stories")
          .update({ moderation_status: status }).eq("id", story.id);
        if (error) throw new Error(`DB error: ${error.message}`);
      }
    } else {
      return json({ error: "unknown kind" }, 400);
    }

    return json({ status });
  } catch (e) {
    console.error("moderate-image error:", String(e));
    return json({ error: "internal error" }, 500);
  }
});
