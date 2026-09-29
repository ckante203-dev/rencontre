// supabase/functions/moderate-image/index.ts
// Appelée par l'app avec le JWT utilisateur (verify_jwt activé).

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

function decide(n: any): "approved" | "pending" | "rejected" {
  const explicit = Math.max(n?.sexual_activity ?? 0, n?.sexual_display ?? 0);
  if (explicit >= 0.85) return "rejected";
  if (explicit >= 0.45 || (n?.erotica ?? 0) >= 0.75) return "pending";
  return "approved";
}

async function scan(url: string): Promise<"approved" | "pending" | "rejected"> {
  try {
    const q = new URLSearchParams({
      url,
      models: "nudity-2.1",
      api_user: Deno.env.get("SIGHTENGINE_USER") ?? "",
      api_secret: Deno.env.get("SIGHTENGINE_SECRET") ?? "",
    });
    const r = await fetch(`https://api.sightengine.com/1.0/check.json?${q}`);
    const j = await r.json();
    if (j.status !== "success") return "pending"; // en cas de doute → admin
    return decide(j.nudity);
  } catch (_) {
    return "pending";
  }
}

// ── Validation de l'URL : fichier public de NOTRE Storage, dans le dossier de l'utilisateur ──
// Formats acceptés : <prefix><bucket>/<uid>/...   (ex. profile-photos/<uid>/x.jpg, avatars/<uid>/photo.jpg)
//                    <prefix><bucket>/<sous-dossier>/<uid>/...   (ex. avatars/avatars/<uid>/profile.jpg)
const PUBLIC_PREFIX = `${SUPABASE_URL.replace(/\/+$/, "")}/storage/v1/object/public/`;
const PROFILE_BUCKETS = ["avatars", "profile-photos"];
const KNOWN_SUBFOLDERS = ["avatars", "photos", "stories"];

function isOwnPublicUrl(url: unknown, uid: string, buckets: string[]): boolean {
  if (typeof url !== "string" || !url.startsWith(PUBLIC_PREFIX)) return false;
  let rest = url.slice(PUBLIC_PREFIX.length).split(/[?#]/)[0];
  try {
    rest = decodeURIComponent(rest);
  } catch (_) {
    return false;
  }
  const segs = rest.split("/");
  if (segs.some((s) => s === "" || s === "." || s === ".." || s.includes("\\"))) return false;
  const [bucket, ...path] = segs;
  if (!buckets.includes(bucket)) return false;
  // path = [<uid>, fichier...]  ou  [<sous-dossier>, <uid>, fichier...]
  if (path.length >= 2 && path[0] === uid) return true;
  if (path.length >= 3 && KNOWN_SUBFOLDERS.includes(path[0]) && path[1] === uid) return true;
  return false;
}

// ── Handler principal ─────────────────────────────────────────────────────
// Appel app (JWT) : { kind: "profile", url } ou { kind: "story", id }
// (url / isVideo éventuellement envoyés pour une story sont ignorés : on lit la ligne en base).
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const user = await getAuthUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const uid = user.id;

    const payload = await req.json().catch(() => null);
    if (!payload || typeof payload !== "object") return json({ error: "invalid body" }, 400);
    const { kind, url, id } = payload as Record<string, unknown>;
    let status: "approved" | "pending" | "rejected";

    if (kind === "profile") {
      if (!isOwnPublicUrl(url, uid, PROFILE_BUCKETS)) {
        return json({ error: "forbidden" }, 403);
      }
      const photoUrl = url as string;
      status = await scan(photoUrl);
      const update = status === "approved"
        ? { photo_url: photoUrl, pending_photo_url: null, photo_status: "approved" }
        : status === "pending"
        ? { pending_photo_url: photoUrl, photo_status: "pending" }
        : { pending_photo_url: null, photo_status: "rejected" };
      const { error } = await admin.from("profiles").update(update).eq("id", uid);
      if (error) throw new Error(`DB error: ${error.message}`);
    } else {
      if ((typeof id !== "string" && typeof id !== "number") || id === "") {
        return json({ error: "Missing fields" }, 400);
      }
      const { data: story, error: stErr } = await admin.from("stories")
        .select("id, media_url, is_video").eq("id", id).eq("user_id", uid).maybeSingle();
      if (stErr) throw new Error(`DB error: ${stErr.message}`);
      if (!story) return json({ error: "forbidden" }, 403);
      if (!story.media_url) return json({ error: "no media" }, 400);

      // Vidéos : revue manuelle pour l'instant (analyse vidéo à ajouter plus tard)
      status = story.is_video === true ? "pending" : await scan(story.media_url);
      const { error } = await admin.from("stories").update({ moderation_status: status }).eq("id", story.id);
      if (error) throw new Error(`DB error: ${error.message}`);
    }

    return json({ status });
  } catch (e) {
    console.error("moderate-image error:", String(e));
    return json({ error: "internal error" }, 500);
  }
});
