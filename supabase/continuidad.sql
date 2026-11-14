-- SmartBuds AI · Continuidad entre dispositivos (ejecutar después de dispositivos.sql).
-- Además de lo que suena, cada dispositivo comparte su cola (máx. 20 canciones),
-- el ambiente y el perfil de uso, para seguir la sesión en otro teléfono o en la
-- página web. Solo tu cuenta lo ve; en modo privado no se comparte nada.

alter table public.user_devices add column if not exists queue jsonb not null default '[]'::jsonb;
alter table public.user_devices add column if not exists mood text;
alter table public.user_devices add column if not exists usage text;

alter table public.user_devices drop constraint if exists user_devices_queue_check;
alter table public.user_devices add constraint user_devices_queue_check
  check (jsonb_typeof(queue) = 'array' and jsonb_array_length(queue) <= 20 and octet_length(queue::text) <= 6000);
alter table public.user_devices drop constraint if exists user_devices_mood_check;
alter table public.user_devices add constraint user_devices_mood_check check (mood is null or char_length(mood) <= 40);
alter table public.user_devices drop constraint if exists user_devices_usage_check;
alter table public.user_devices add constraint user_devices_usage_check check (usage is null or char_length(usage) <= 20);

-- Igual que upsert_my_device, con la cola, el ambiente y el perfil.
drop function if exists public.upsert_my_device2(text, text, text, text, text, text, boolean, jsonb, text, text);
create or replace function public.upsert_my_device2(
  p_device_id text, p_name text, p_platform text,
  p_title text, p_artist text, p_app text, p_playing boolean,
  p_queue jsonb, p_mood text, p_usage text
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  q jsonb;
begin
  if uid is null then raise exception 'Necesitas una cuenta'; end if;
  -- Solo textos, máximo 20, cada uno de hasta 200 caracteres.
  select coalesce(jsonb_agg(left(v, 200)), '[]'::jsonb) into q
  from (select value #>> '{}' as v from jsonb_array_elements(
          case when jsonb_typeof(p_queue) = 'array' then p_queue else '[]'::jsonb end) with ordinality as t(value, n)
        where jsonb_typeof(value) = 'string' and n <= 20 order by n) s;
  perform pg_advisory_xact_lock(hashtextextended('devices:' || uid::text, 0));
  if not exists (select 1 from user_devices where user_id = uid and device_id = p_device_id)
     and (select count(*) from user_devices where user_id = uid) >= 10 then
    raise exception 'Máximo 10 dispositivos. Quita uno que ya no uses.';
  end if;
  insert into user_devices (user_id, device_id, name, platform, title, artist, app, playing, queue, mood, usage, updated_at)
  values (uid, p_device_id, trim(p_name), p_platform, left(p_title, 200), left(p_artist, 200), left(p_app, 60),
          coalesce(p_playing, false), q, left(p_mood, 40), left(p_usage, 20), now())
  on conflict (user_id, device_id) do update set
    name = excluded.name, platform = excluded.platform, title = excluded.title, artist = excluded.artist,
    app = excluded.app, playing = excluded.playing, queue = excluded.queue, mood = excluded.mood,
    usage = excluded.usage, updated_at = now();
end $$;

revoke all on function public.upsert_my_device2(text, text, text, text, text, text, boolean, jsonb, text, text) from public, anon;
grant execute on function public.upsert_my_device2(text, text, text, text, text, text, boolean, jsonb, text, text) to authenticated;
