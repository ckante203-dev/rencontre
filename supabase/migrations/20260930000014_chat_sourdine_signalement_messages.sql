-- Menu de conversation :
--   1. « Couper les notifications » d'une conversation (table
--      conversation_sourdines, lue par la fonction smooth-action).
--   2. Signalement d'un message (colonnes message_* de `reports`).
--
-- L'app fonctionne sans ce script : l'interrupteur de sourdine affiche
-- une erreur, et un message signalé est enregistré comme un signalement
-- de profil (motif préfixé par « Message : »).

-- ─── 1. Sourdine par conversation ───────────────────────────────────
create table if not exists public.conversation_sourdines (
  user_id         uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid not null,
  created_at      timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

-- Suppression automatique quand la conversation est supprimée
-- (ignoré si le type de conversations.id ne correspond pas).
do $$
begin
  alter table public.conversation_sourdines
    add constraint conversation_sourdines_conversation_fk
    foreign key (conversation_id) references public.conversations(id)
    on delete cascade;
exception when others then
  raise notice 'clé étrangère conversation_sourdines non créée : %', sqlerrm;
end $$;

alter table public.conversation_sourdines enable row level security;

drop policy if exists sourdines_select on public.conversation_sourdines;
create policy sourdines_select on public.conversation_sourdines
  for select to authenticated using (user_id = auth.uid());

drop policy if exists sourdines_insert on public.conversation_sourdines;
create policy sourdines_insert on public.conversation_sourdines
  for insert to authenticated with check (
    user_id = auth.uid()
    and exists (select 1 from public.conversations c
                where c.id = conversation_id
                  and auth.uid() in (c.user1_id, c.user2_id))
  );

drop policy if exists sourdines_delete on public.conversation_sourdines;
create policy sourdines_delete on public.conversation_sourdines
  for delete to authenticated using (user_id = auth.uid());

revoke all on public.conversation_sourdines from anon;
grant select, insert, delete on public.conversation_sourdines to authenticated;

-- ─── 2. Signalement d'un message ────────────────────────────────────
-- Copie du contenu au moment du signalement : le message est supprimé
-- 24h après lecture, traiter ces signalements vite.
alter table public.reports
  add column if not exists message_id text,
  add column if not exists message_contenu text,
  add column if not exists message_media_url text;

-- Un signalement par message ; l'unicité « par profil » (si elle existe)
-- ne doit pas empêcher de signaler un message d'un profil déjà signalé.
create unique index if not exists reports_unique_message
  on public.reports (reporter_id, message_id)
  where message_id is not null;

do $$
begin
  if exists (select 1 from pg_indexes
             where schemaname = 'public' and indexname = 'reports_unique_profil') then
    drop index public.reports_unique_profil;
    create unique index reports_unique_profil
      on public.reports (reporter_id, reported_id)
      where story_id is null and message_id is null;
  end if;
end $$;
