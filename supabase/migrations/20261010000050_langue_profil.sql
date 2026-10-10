-- 050 : langue choisie dans l'app (fr / en), pour les notifications traduites plus tard.
alter table public.profiles
  add column if not exists langue text not null default 'fr'
  check (langue in ('fr', 'en'));
