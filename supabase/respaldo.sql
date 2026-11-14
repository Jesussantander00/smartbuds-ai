-- SmartBuds AI · Copia de seguridad en la nube (ejecutar después de schema.sql).
-- Una copia por cuenta (se sobrescribe): tus preferencias, perfiles,
-- automatizaciones y gustos. Solo tu cuenta la ve. Máximo ~2 MB.

create table if not exists public.user_backups (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  device text check (device is null or char_length(device) <= 40),
  data jsonb not null check (jsonb_typeof(data) = 'object' and octet_length(data::text) < 2000000),
  updated_at timestamptz not null default now()
);
alter table public.user_backups enable row level security;

revoke all on public.user_backups from anon;
grant select, insert, update, delete on public.user_backups to authenticated;

drop policy if exists "ver mi copia" on public.user_backups;
create policy "ver mi copia" on public.user_backups
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "crear mi copia" on public.user_backups;
create policy "crear mi copia" on public.user_backups
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "cambiar mi copia" on public.user_backups;
create policy "cambiar mi copia" on public.user_backups
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "borrar mi copia" on public.user_backups;
create policy "borrar mi copia" on public.user_backups
  for delete to authenticated using (user_id = auth.uid());

-- La fecha la pone el servidor (no el teléfono).
create or replace function public.touch_user_backup() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists user_backups_touch on public.user_backups;
create trigger user_backups_touch before insert or update on public.user_backups
  for each row execute function public.touch_user_backup();
