-- SmartBuds AI · Refuerzo de seguridad (ejecutar DESPUÉS de schema.sql y cuentas.sql,
-- y cuando la app ya envíe la cabecera x-device-id, es decir, desde la versión del PR #6).
--
-- Antes: sin cuenta, la clave pública podía leer y modificar las puntuaciones
-- anónimas de CUALQUIER teléfono. Ahora cada teléfono solo ve y cambia las suyas:
-- la fila debe tener el mismo device_id que la cabecera x-device-id de la petición.

create or replace function public.request_device_id() returns text
language sql stable as $$
  select coalesce(
    (current_setting('request.headers', true)::json ->> 'x-device-id'),
    ''
  )
$$;

alter policy "app inserta eventos" on public.listening_events
  with check (user_id is null and device_id not like 'u:%'
              and device_id = public.request_device_id());

alter policy "app inserta puntuaciones" on public.track_scores
  with check (user_id is null and device_id not like 'u:%'
              and device_id = public.request_device_id());

alter policy "app actualiza puntuaciones" on public.track_scores
  using (user_id is null and device_id = public.request_device_id())
  with check (user_id is null and device_id not like 'u:%'
              and device_id = public.request_device_id());

alter policy "app lee puntuaciones para upsert" on public.track_scores
  using (user_id is null and device_id = public.request_device_id());

-- Los reportes de errores solo se pueden escribir (nunca leer) desde la app.
revoke select on public.app_errors from anon, authenticated;
