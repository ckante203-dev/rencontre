-- Signalement des stories (exigence Google Play : tout contenu publié
-- par un utilisateur doit pouvoir être signalé).
--
-- Un signalement de story est une ligne de `reports` avec :
--   reported_id     = auteur de la story
--   story_id        = la story signalée
--   story_media_url / story_text = copie du contenu au moment du
--                     signalement (la story et son fichier sont purgés
--                     à l'expiration : traiter les signalements vite).
--
-- L'app fonctionne sans ce script (elle enregistre alors le signalement
-- comme un signalement de profil, motif préfixé par « Story : »).

alter table public.reports
  add column if not exists story_id text,
  add column if not exists story_media_url text,
  add column if not exists story_text text;

-- Unicité : l'ancienne règle « un signalement par (signaleur, profil) »
-- empêcherait de signaler la story d'un profil déjà signalé. On la
-- remplace par : un signalement par profil (hors story) et un par story.
do $$
declare
  r record;
  had_unique boolean := false;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.reports'::regclass
      and c.contype = 'u'
      and (select array_agg(a.attname::text order by a.attname)
           from unnest(c.conkey) k
           join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k)
          = array['reported_id', 'reporter_id']
  loop
    execute format('alter table public.reports drop constraint %I', r.conname);
    had_unique := true;
  end loop;

  for r in
    select i.indexrelid::regclass::text as idx
    from pg_index i
    where i.indrelid = 'public.reports'::regclass
      and i.indisunique
      and not i.indisprimary
      and i.indpred is null
      and not exists (select 1 from pg_constraint c where c.conindid = i.indexrelid)
      and (select array_agg(a.attname::text order by a.attname)
           from unnest(i.indkey::int2[]) k
           join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k)
          = array['reported_id', 'reporter_id']
  loop
    execute format('drop index %s', r.idx);
    had_unique := true;
  end loop;

  -- On ne recrée l'unicité par profil que si elle existait déjà
  -- (sinon d'anciens doublons feraient échouer la création).
  if had_unique then
    execute 'create unique index if not exists reports_unique_profil
             on public.reports (reporter_id, reported_id)
             where story_id is null';
  end if;
end $$;

create unique index if not exists reports_unique_story
  on public.reports (reporter_id, story_id)
  where story_id is not null;
