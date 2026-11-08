-- SmartBuds AI — reportes anónimos de errores.
-- Ejecutar una vez: SQL Editor → New query → pegar → Run.
-- La app solo puede INSERTAR; nadie puede leerlos desde la app (solo tú, en el panel).

create table if not exists public.app_errors (
  id          bigint generated always as identity primary key,
  device_id   text        not null,
  platform    text,
  os_version  text,
  kind        text        not null,
  message     text,
  created_at  timestamptz not null default now()
);

create index if not exists app_errors_created_idx on public.app_errors (created_at desc);

alter table public.app_errors enable row level security;

drop policy if exists "app reporta errores" on public.app_errors;
create policy "app reporta errores" on public.app_errors
  for insert to anon, authenticated
  with check (char_length(coalesce(message, '')) <= 500 and char_length(kind) <= 60);

grant insert on public.app_errors to anon, authenticated;
grant usage on all sequences in schema public to anon, authenticated;
