-- SmartBuds AI · Centro multidispositivo (ejecutar después de schema.sql y cuentas.sql).
-- Cada teléfono con tu cuenta publica qué está sonando para que lo veas desde
-- tus otros dispositivos. Solo tu cuenta lo ve. No se guarda historial: una fila
-- por dispositivo que se sobrescribe. Máximo 10 dispositivos por cuenta.

create table if not exists public.user_devices (
  user_id uuid not null references auth.users (id) on delete cascade,
  device_id text not null check (device_id ~ '^[0-9a-f]{16,64}$'),
  name text not null check (char_length(trim(name)) between 1 and 40),
  platform text not null check (platform in ('android', 'ios', 'web', 'other')),
  title text check (title is null or char_length(title) <= 200),
  artist text check (artist is null or char_length(artist) <= 200),
  app text check (app is null or char_length(app) <= 60),
  playing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);
alter table public.user_devices enable row level security;

revoke all on public.user_devices from anon;
revoke insert, update on public.user_devices from authenticated;
grant select, delete on public.user_devices to authenticated;

drop policy if exists "ver mis dispositivos" on public.user_devices;
create policy "ver mis dispositivos" on public.user_devices
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "quitar mis dispositivos" on public.user_devices;
create policy "quitar mis dispositivos" on public.user_devices
  for delete to authenticated using (user_id = auth.uid());

-- Publicar el estado de este dispositivo (crear o actualizar su fila).
-- La escritura solo pasa por aquí: valida, limita a 10 por cuenta y es atómica.
drop function if exists public.upsert_my_device(text, text, text, text, text, text, boolean);
create or replace function public.upsert_my_device(
  p_device_id text, p_name text, p_platform text,
  p_title text, p_artist text, p_app text, p_playing boolean
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Necesitas una cuenta'; end if;
  perform pg_advisory_xact_lock(hashtextextended('devices:' || uid::text, 0));
  if not exists (select 1 from user_devices where user_id = uid and device_id = p_device_id)
     and (select count(*) from user_devices where user_id = uid) >= 10 then
    raise exception 'Máximo 10 dispositivos. Quita uno que ya no uses.';
  end if;
  insert into user_devices (user_id, device_id, name, platform, title, artist, app, playing, updated_at)
  values (uid, p_device_id, trim(p_name), p_platform,
          left(p_title, 200), left(p_artist, 200), left(p_app, 60), coalesce(p_playing, false), now())
  on conflict (user_id, device_id) do update set
    name = excluded.name, platform = excluded.platform, title = excluded.title,
    artist = excluded.artist, app = excluded.app, playing = excluded.playing, updated_at = now();
end $$;

revoke all on function public.upsert_my_device(text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.upsert_my_device(text, text, text, text, text, text, boolean) to authenticated;
