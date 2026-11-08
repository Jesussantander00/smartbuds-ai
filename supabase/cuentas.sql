-- SmartBuds AI — cuentas con correo (Supabase Auth).
-- Ejecutar una vez DESPUÉS de schema.sql: SQL Editor → New query → pegar → Run.
--
-- Sin cuenta: la app escribe con la clave pública (anon) y un device_id anónimo.
-- Con cuenta: escribe con el token del usuario; device_id = 'u:<id>' y
-- user_id = su id. Cada usuario solo puede leer y cambiar sus propios datos.

alter table public.listening_events
  add column if not exists user_id uuid references auth.users (id) on delete cascade;
alter table public.track_scores
  add column if not exists user_id uuid references auth.users (id) on delete cascade;

create index if not exists track_scores_user_idx on public.track_scores (user_id);

-- Las políticas anónimas ya no pueden tocar datos de cuentas.
-- (y no pueden usar identificadores de cuenta «u:…»).
alter policy "app inserta eventos" on public.listening_events
  with check (user_id is null and device_id not like 'u:%');
alter policy "app inserta puntuaciones" on public.track_scores
  with check (user_id is null and device_id not like 'u:%');
alter policy "app actualiza puntuaciones" on public.track_scores
  using (user_id is null) with check (user_id is null and device_id not like 'u:%');
alter policy "app lee puntuaciones para upsert" on public.track_scores
  using (user_id is null);

-- Usuarios con sesión: solo lo suyo.
drop policy if exists "usuario inserta sus eventos" on public.listening_events;
create policy "usuario inserta sus eventos" on public.listening_events
  for insert to authenticated
  with check (user_id = auth.uid() and device_id = 'u:' || auth.uid()::text);

drop policy if exists "usuario lee sus eventos" on public.listening_events;
create policy "usuario lee sus eventos" on public.listening_events
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "usuario inserta sus puntuaciones" on public.track_scores;
create policy "usuario inserta sus puntuaciones" on public.track_scores
  for insert to authenticated
  with check (user_id = auth.uid() and device_id = 'u:' || auth.uid()::text);

drop policy if exists "usuario actualiza sus puntuaciones" on public.track_scores;
create policy "usuario actualiza sus puntuaciones" on public.track_scores
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and device_id = 'u:' || auth.uid()::text);

drop policy if exists "usuario lee sus puntuaciones" on public.track_scores;
create policy "usuario lee sus puntuaciones" on public.track_scores
  for select to authenticated using (user_id = auth.uid());

grant usage on schema public to authenticated;
grant select, insert on public.listening_events to authenticated;
grant select, insert, update on public.track_scores to authenticated;
grant usage on all sequences in schema public to authenticated;
