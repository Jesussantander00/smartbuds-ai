-- SmartBuds AI — tablas del perfil musical (Supabase / PostgreSQL)
-- Ejecutar una vez en Supabase: SQL Editor → New query → pegar → Run.
--
-- Versión de prototipo: cada teléfono se identifica con un device_id anónimo
-- y la app escribe con la clave pública (anon). Cuando haya inicio de sesión
-- (Supabase Auth), cambiar device_id por auth.uid() y endurecer las políticas.

create table if not exists public.listening_events (
  id           bigint generated always as identity primary key,
  device_id    text        not null,
  track_key    text        not null,
  title        text        not null,
  artist       text,
  app_package  text,
  event_type   text        not null check (event_type in
               ('play', 'complete', 'skip', 'repeat', 'like', 'dislike')),
  happened_at  timestamptz not null default now()
);

create index if not exists listening_events_device_idx
  on public.listening_events (device_id, happened_at desc);

create table if not exists public.track_scores (
  device_id      text not null,
  track_key      text not null,
  title          text not null,
  artist         text,
  plays          int  not null default 0,
  completes      int  not null default 0,
  skips          int  not null default 0,
  repeats        int  not null default 0,
  likes          int  not null default 0,
  dislikes       int  not null default 0,
  last_played_at timestamptz,
  updated_at     timestamptz not null default now(),
  primary key (device_id, track_key)
);

alter table public.listening_events enable row level security;
alter table public.track_scores     enable row level security;

-- Prototipo: la app solo puede insertar y actualizar; no puede leer ni borrar
-- datos de otros dispositivos desde el cliente.
create policy "app inserta eventos" on public.listening_events
  for insert to anon with check (true);

create policy "app inserta puntuaciones" on public.track_scores
  for insert to anon with check (true);

create policy "app actualiza puntuaciones" on public.track_scores
  for update to anon using (true) with check (true);

-- PostgreSQL exige permiso de lectura para «insertar o actualizar» (upsert).
-- En el prototipo se permite; con Supabase Auth se limita a auth.uid().
create policy "app lee puntuaciones para upsert" on public.track_scores
  for select to anon using (true);

-- Permisos de la API (Data API). Supabase puede crear el proyecto sin
-- exponer tablas nuevas automáticamente, así que se conceden explícitamente.
grant usage on schema public to anon;
grant insert on public.listening_events to anon;
grant select, insert, update on public.track_scores to anon;
grant usage on all sequences in schema public to anon;
