-- Boost de profil (1h / 2h / 24h), acheté dans l'app (produits Google
-- Play boost_1h, boost_2h, boost_24h via RevenueCat).
--
-- Le Boost est accordé UNIQUEMENT par le serveur : le webhook RevenueCat
-- (fonction swift-service) appelle appliquer_boost() après confirmation
-- du paiement. Le client ne peut pas modifier boost_jusqua.
--
-- Compatible avec la 1.0.11 en production : nouvelle colonne nullable,
-- ignorée par les anciennes versions de l'app.

-- ─── 1. Date de fin du Boost ────────────────────────────────────────
alter table public.profiles
  add column if not exists boost_jusqua timestamptz;

create index if not exists profiles_boost_jusqua_idx
  on public.profiles (boost_jusqua)
  where boost_jusqua is not null;

-- ─── 2. Achats de Boost déjà appliqués (anti-doublon) ───────────────
-- RevenueCat peut renvoyer le même événement : une transaction n'est
-- comptée qu'une fois.
create table if not exists public.boost_achats (
  transaction_id text primary key,
  user_id        uuid not null references auth.users(id) on delete cascade,
  produit        text not null,
  minutes        int  not null check (minutes > 0),
  created_at     timestamptz not null default now()
);

alter table public.boost_achats enable row level security;
-- Aucune policy : lecture/écriture réservées au serveur (service_role).
revoke all on public.boost_achats from anon, authenticated;

-- ─── 3. Le client ne peut pas se donner un Boost ────────────────────
create or replace function public.protect_boost_column()
returns trigger
language plpgsql
as $$
begin
  -- service_role, postgres, fonctions SECURITY DEFINER : autorisés
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.boost_jusqua := null;
    return new;
  end if;

  if new.boost_jusqua is distinct from old.boost_jusqua then
    raise exception 'Modification de boost_jusqua non autorisée'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_boost on public.profiles;
create trigger trg_protect_boost
  before insert or update on public.profiles
  for each row execute function public.protect_boost_column();

-- ─── 4. Application d'un Boost (appelée par le webhook) ─────────────
-- Prolonge un Boost en cours, sinon démarre maintenant.
-- Renvoie la nouvelle date de fin.
create or replace function public.appliquer_boost(
  p_user        uuid,
  p_transaction text,
  p_produit     text,
  p_minutes     int
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fin timestamptz;
begin
  -- Pas de profil pour cet id : rien n'est enregistré (le webhook
  -- essaie alors l'id suivant).
  if not exists (select 1 from public.profiles where id = p_user) then
    return null;
  end if;

  insert into public.boost_achats (transaction_id, user_id, produit, minutes)
  values (p_transaction, p_user, p_produit, p_minutes)
  on conflict (transaction_id) do nothing;

  if not found then
    -- Déjà appliqué (événement reçu deux fois)
    select boost_jusqua into v_fin from public.profiles where id = p_user;
    return v_fin;
  end if;

  update public.profiles
     set boost_jusqua = greatest(coalesce(boost_jusqua, now()), now())
                        + make_interval(mins => p_minutes)
   where id = p_user
  returning boost_jusqua into v_fin;

  return v_fin;
end;
$$;

revoke all on function public.appliquer_boost(uuid, text, text, int)
  from public, anon, authenticated;
grant execute on function public.appliquer_boost(uuid, text, text, int)
  to service_role;
