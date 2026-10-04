-- ═══════════════════════════════════════════════════════════════════
-- Événements (match, concert, festival…) — 2026-10-04
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- • evenements : créés par Zamu (admins) depuis le panneau d'admin.
--   Visibles par tous les connectés une fois publiés.
-- • evenement_participants : « ✋ J'y vais ». Tout le monde voit le
--   NOMBRE de participants ; seuls les participants voient QUI vient
--   (hors blocages et comptes suspendus).
-- • bucket « evenements » (public) : affiches, envoyées par les admins.
-- • RPC pour l'app :
--     evenements_a_venir()            → liste + nombre + « j'y vais »
--     participants_evenement(id)      → profils (si je participe)
--     participants_mes_evenements()   → ids des gens qui vont aux mêmes
--                                       événements que moi (badge / filtre)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Tables ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.evenements (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titre       text NOT NULL CHECK (char_length(btrim(titre)) BETWEEN 3 AND 80),
  description text CHECK (description IS NULL OR char_length(description) <= 1000),
  categorie   text NOT NULL DEFAULT 'autre'
              CHECK (categorie IN ('sport', 'concert', 'soiree', 'festival', 'autre')),
  lieu        text NOT NULL CHECK (char_length(btrim(lieu)) BETWEEN 2 AND 120),
  ville       text CHECK (ville IS NULL OR char_length(ville) <= 60),
  latitude    double precision,
  longitude   double precision,
  debut       timestamptz NOT NULL,
  fin         timestamptz,
  image_url   text CHECK (image_url IS NULL OR image_url ~ '^https://'),
  statut      text NOT NULL DEFAULT 'publie'
              CHECK (statut IN ('publie', 'brouillon', 'annule')),
  cree_par    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (fin IS NULL OR fin > debut)
);
CREATE INDEX IF NOT EXISTS evenements_debut_idx ON public.evenements (debut);

CREATE TABLE IF NOT EXISTS public.evenement_participants (
  evenement_id uuid NOT NULL REFERENCES public.evenements(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (evenement_id, user_id)
);
CREATE INDEX IF NOT EXISTS evenement_participants_user_idx
  ON public.evenement_participants (user_id);

-- Fin effective : la fin indiquée, sinon 12 h après le début
CREATE OR REPLACE FUNCTION public.fin_evenement(e public.evenements)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(e.fin, e.debut + interval '12 hours');
$$;

-- Vrai si `p_user` participe à l'événement
CREATE OR REPLACE FUNCTION public.participe_evenement(p_ev uuid, p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM evenement_participants
                 WHERE evenement_id = p_ev AND user_id = p_user);
$$;
REVOKE ALL ON FUNCTION public.participe_evenement(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.participe_evenement(uuid, uuid) TO authenticated;

-- ── 2. Règles d'accès ──────────────────────────────────────────────
ALTER TABLE public.evenements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS evenements_select ON public.evenements;
CREATE POLICY evenements_select ON public.evenements
  FOR SELECT TO authenticated
  USING (statut <> 'brouillon' OR public.is_admin());

DROP POLICY IF EXISTS evenements_admin ON public.evenements;
CREATE POLICY evenements_admin ON public.evenements
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

ALTER TABLE public.evenement_participants ENABLE ROW LEVEL SECURITY;

-- Je vois ma participation ; les participants se voient entre eux
DROP POLICY IF EXISTS evenement_participants_select ON public.evenement_participants;
CREATE POLICY evenement_participants_select ON public.evenement_participants
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_admin()
    OR (public.participe_evenement(evenement_id, auth.uid())
        AND NOT public.blocage_entre(user_id, auth.uid()))
  );

-- « J'y vais » : pour moi seulement, sur un événement publié pas terminé
DROP POLICY IF EXISTS evenement_participants_insert ON public.evenement_participants;
CREATE POLICY evenement_participants_insert ON public.evenement_participants
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.evenements e
                WHERE e.id = evenement_id
                  AND e.statut = 'publie'
                  AND public.fin_evenement(e) > now())
  );

DROP POLICY IF EXISTS evenement_participants_delete ON public.evenement_participants;
CREATE POLICY evenement_participants_delete ON public.evenement_participants
  FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- ── 3. Fonctions pour l'app ────────────────────────────────────────
-- Événements à venir / en cours, avec le nombre de participants
DROP FUNCTION IF EXISTS public.evenements_a_venir();
CREATE FUNCTION public.evenements_a_venir()
RETURNS TABLE (
  id uuid, titre text, description text, categorie text, lieu text,
  ville text, latitude double precision, longitude double precision,
  debut timestamptz, fin timestamptz, image_url text, statut text,
  nb_participants int, je_participe boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT e.id, e.titre, e.description, e.categorie, e.lieu, e.ville,
         e.latitude, e.longitude, e.debut, e.fin, e.image_url, e.statut,
         (SELECT count(*)::int FROM evenement_participants p
            JOIN profiles pr ON pr.id = p.user_id
           WHERE p.evenement_id = e.id
             AND NOT COALESCE(pr.is_suspended, false)),
         EXISTS (SELECT 1 FROM evenement_participants p
                  WHERE p.evenement_id = e.id AND p.user_id = auth.uid())
  FROM evenements e
  WHERE auth.uid() IS NOT NULL
    AND e.statut IN ('publie', 'annule')
    AND public.fin_evenement(e) > now()
  ORDER BY e.debut
  LIMIT 50;
$$;
REVOKE ALL ON FUNCTION public.evenements_a_venir() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.evenements_a_venir() TO authenticated;

-- Qui vient (seulement si je participe moi-même)
DROP FUNCTION IF EXISTS public.participants_evenement(uuid);
CREATE FUNCTION public.participants_evenement(p_ev uuid)
RETURNS TABLE (id uuid, name text, photo_url text, username text,
               en_ligne boolean, inscrit_le timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT pr.id, pr.name::text, pr.photo_url::text, pr.username::text,
         COALESCE(pr.last_seen > now() - interval '30 minutes', false),
         p.created_at
  FROM evenement_participants p
  JOIN profiles pr ON pr.id = p.user_id
  WHERE p.evenement_id = p_ev
    AND public.participe_evenement(p_ev, auth.uid())
    AND pr.id <> auth.uid()
    AND NOT COALESCE(pr.is_suspended, false)
    AND NOT public.blocage_entre(pr.id, auth.uid())
  ORDER BY p.created_at DESC
  LIMIT 300;
$$;
REVOKE ALL ON FUNCTION public.participants_evenement(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.participants_evenement(uuid) TO authenticated;

-- Personnes qui vont aux mêmes événements (à venir) que moi
DROP FUNCTION IF EXISTS public.participants_mes_evenements();
CREATE FUNCTION public.participants_mes_evenements()
RETURNS TABLE (user_id uuid, evenement_id uuid, titre text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT DISTINCT ON (p.user_id) p.user_id, e.id, e.titre
  FROM evenement_participants moi
  JOIN evenements e ON e.id = moi.evenement_id
  JOIN evenement_participants p ON p.evenement_id = e.id
  WHERE moi.user_id = auth.uid()
    AND p.user_id <> auth.uid()
    AND e.statut = 'publie'
    AND public.fin_evenement(e) > now()
    AND NOT public.blocage_entre(p.user_id, auth.uid())
  ORDER BY p.user_id, e.debut;
$$;
REVOKE ALL ON FUNCTION public.participants_mes_evenements() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.participants_mes_evenements() TO authenticated;

-- ── 4. Affiches (Storage) ──────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('evenements', 'evenements', true, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS evenements_affiche_envoi ON storage.objects;
CREATE POLICY evenements_affiche_envoi ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'evenements' AND public.is_admin());

DROP POLICY IF EXISTS evenements_affiche_maj ON storage.objects;
CREATE POLICY evenements_affiche_maj ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'evenements' AND public.is_admin());

DROP POLICY IF EXISTS evenements_affiche_suppression ON storage.objects;
CREATE POLICY evenements_affiche_suppression ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'evenements' AND public.is_admin());

COMMIT;

NOTIFY pgrst, 'reload schema';
