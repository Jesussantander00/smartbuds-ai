-- SmartBuds AI · Funciones sociales (ejecutar después de schema.sql, cuentas.sql y seguridad.sql).
-- Todo requiere cuenta. Nadie ve el historial de nadie: solo lo que cada quien
-- decide compartir (perfil público opcional, listas compartidas y canciones enviadas).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- Perfil público
-- Opcional: nombre visible, código de amigo y artistas favoritos (nunca el historial).
create table if not exists public.social_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 40),
  -- top_artists: máx. 15 nombres

  friend_code text not null unique check (friend_code ~ '^[A-Z2-9]{6}$'),
  top_artists jsonb not null default '[]'::jsonb check (jsonb_typeof(top_artists) = 'array' and jsonb_array_length(top_artists) <= 15),
  is_public boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.social_profiles enable row level security;

drop policy if exists "ver perfiles públicos o el mío" on public.social_profiles;
create policy "ver perfiles públicos o el mío" on public.social_profiles
  for select to authenticated using (is_public or user_id = auth.uid());
drop policy if exists "crear mi perfil" on public.social_profiles;
create policy "crear mi perfil" on public.social_profiles
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "editar mi perfil" on public.social_profiles;
create policy "editar mi perfil" on public.social_profiles
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "borrar mi perfil" on public.social_profiles;
create policy "borrar mi perfil" on public.social_profiles
  for delete to authenticated using (user_id = auth.uid());

-- Buscar a alguien por su código de amigo (aunque su perfil no sea público).
-- Solo devuelve el nombre; los artistas se ven cuando la amistad es mutua (my_contacts).
drop function if exists public.profile_by_code(text);
create or replace function public.profile_by_code(code text)
returns table (user_id uuid, display_name text)
language sql stable security definer set search_path = public, pg_temp as $$
  select p.user_id, p.display_name
  from public.social_profiles p
  where p.friend_code = upper(trim(code)) and auth.uid() is not null
  limit 1
$$;
revoke all on function public.profile_by_code(text) from public, anon;
grant execute on function public.profile_by_code(text) to authenticated;

-- ---------------------------------------------------------- Listas compartidas
create table if not exists public.shared_playlists (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  invite_code text not null unique default upper(encode(gen_random_bytes(6), 'hex')), -- 12 caracteres
  created_at timestamptz not null default now()
);
create table if not exists public.playlist_members (
  playlist_id uuid not null references public.shared_playlists (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (playlist_id, user_id)
);
create table if not exists public.playlist_items (
  id bigserial primary key,
  playlist_id uuid not null references public.shared_playlists (id) on delete cascade,
  added_by uuid not null references auth.users (id) on delete cascade,
  added_by_name text,
  title text not null check (char_length(title) between 1 and 200),
  artist text check (char_length(artist) <= 200),
  created_at timestamptz not null default now()
);
alter table public.shared_playlists enable row level security;
alter table public.playlist_members enable row level security;
alter table public.playlist_items enable row level security;

create or replace function public.is_playlist_member(pid uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.playlist_members m where m.playlist_id = pid and m.user_id = auth.uid())
$$;
revoke all on function public.is_playlist_member(uuid) from public, anon;
grant execute on function public.is_playlist_member(uuid) to authenticated;

drop policy if exists "ver mis listas" on public.shared_playlists;
create policy "ver mis listas" on public.shared_playlists
  for select to authenticated using (owner = auth.uid() or public.is_playlist_member(id));
drop policy if exists "crear listas" on public.shared_playlists;
-- Se crea solo con create_playlist().
drop policy if exists "borrar mis listas" on public.shared_playlists;
create policy "borrar mis listas" on public.shared_playlists
  for delete to authenticated using (owner = auth.uid());

drop policy if exists "ver miembros de mis listas" on public.playlist_members;
create policy "ver miembros de mis listas" on public.playlist_members
  for select to authenticated using (public.is_playlist_member(playlist_id));
drop policy if exists "salir de una lista" on public.playlist_members;
create policy "salir de una lista" on public.playlist_members
  for delete to authenticated using (user_id = auth.uid());
-- Unirse solo con el código de invitación (función de abajo), nunca directo.

drop policy if exists "ver canciones de mis listas" on public.playlist_items;
create policy "ver canciones de mis listas" on public.playlist_items
  for select to authenticated using (public.is_playlist_member(playlist_id));
drop policy if exists "agregar a mis listas" on public.playlist_items;
-- Se agrega solo con add_playlist_item() (valida y limita).
drop policy if exists "quitar lo que agregué" on public.playlist_items;
create policy "quitar lo que agregué" on public.playlist_items
  for delete to authenticated using (added_by = auth.uid());

-- Crear una lista y quedar como miembro.
create or replace function public.create_playlist(list_name text)
returns public.shared_playlists language plpgsql security definer set search_path = public, pg_temp as $$
declare p public.shared_playlists;
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  if list_name is null or char_length(trim(list_name)) not between 1 and 60 then
    raise exception 'El nombre debe tener entre 1 y 60 letras';
  end if;
  -- Candado por usuario: las solicitudes simultáneas esperan su turno (los límites no se pueden saltar).
  perform pg_advisory_xact_lock(hashtextextended('list:' || auth.uid()::text, 0));
  if (select count(*) from public.shared_playlists where owner = auth.uid()) >= 20 then
    raise exception 'Ya tienes 20 listas. Borra alguna para crear otra.';
  end if;
  insert into public.shared_playlists (owner, name) values (auth.uid(), trim(list_name)) returning * into p;
  insert into public.playlist_members (playlist_id, user_id) values (p.id, auth.uid());
  return p;
end $$;
revoke all on function public.create_playlist(text) from public, anon;
grant execute on function public.create_playlist(text) to authenticated;

-- Unirse con el código de invitación.
-- Intentos de unirse (para frenar a quien prueba códigos al azar).
create table if not exists public.join_attempts (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  ok boolean not null,
  at timestamptz not null default now()
);
alter table public.join_attempts enable row level security; -- sin políticas: nadie la lee desde la app

create or replace function public.join_playlist(code text)
returns public.shared_playlists language plpgsql security definer set search_path = public, pg_temp as $$
declare p public.shared_playlists; fails int; members int;
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  -- Candado por usuario: las solicitudes simultáneas esperan su turno (los límites no se pueden saltar).
  perform pg_advisory_xact_lock(hashtextextended('join:' || auth.uid()::text, 0));
  select count(*) into fails from public.join_attempts
    where user_id = auth.uid() and not ok and at > now() - interval '1 hour';
  if fails >= 10 then raise exception 'Demasiados intentos. Prueba en una hora.'; end if;
  if code is null or char_length(trim(code)) not between 6 and 16 then
    insert into public.join_attempts (user_id, ok) values (auth.uid(), false);
    return null; -- también cuenta como intento fallido
  end if;
  select * into p from public.shared_playlists where invite_code = upper(trim(code));
  if p.id is null then
    -- Sin «raise»: así el intento fallido queda guardado (un error lo desharía).
    insert into public.join_attempts (user_id, ok) values (auth.uid(), false);
    return null; -- la app muestra «Código no válido»
  end if;
  select count(*) into members from public.playlist_members where playlist_id = p.id;
  if members >= 50 then raise exception 'La lista ya está llena (50 personas).'; end if;
  insert into public.join_attempts (user_id, ok) values (auth.uid(), true);
  insert into public.playlist_members (playlist_id, user_id) values (p.id, auth.uid())
    on conflict do nothing;
  return p;
end $$;
revoke all on function public.join_playlist(text) from public, anon;
grant execute on function public.join_playlist(text) to authenticated;

-- ------------------------------------------------- Canciones enviadas entre amigos
create table if not exists public.song_shares (
  id bigserial primary key,
  from_user uuid not null references auth.users (id) on delete cascade,
  to_user uuid not null references auth.users (id) on delete cascade,
  anonymous boolean not null default false,
  title text not null check (char_length(title) between 1 and 200),
  artist text check (char_length(artist) <= 200),
  message text check (char_length(message) <= 200),
  seen boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.song_shares enable row level security;

drop policy if exists "enviar canciones" on public.song_shares;
-- Se envía solo con send_song(): exige amistad mutua y limita la cantidad.
drop policy if exists "ver lo que envié" on public.song_shares;
create policy "ver lo que envié" on public.song_shares
  for select to authenticated using (from_user = auth.uid());
-- El que recibe NO lee la tabla directo (vería quién la mandó aunque sea anónima):
-- usa my_inbox(), que oculta al remitente cuando es anónimo.

create or replace function public.my_inbox()
returns table (id bigint, from_name text, title text, artist text, message text, seen boolean, created_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select s.id,
         case when s.anonymous then null else coalesce(p.display_name, 'Un amigo') end,
         s.title, s.artist, s.message, s.seen, s.created_at
  from public.song_shares s
  left join public.social_profiles p on p.user_id = s.from_user
  where s.to_user = auth.uid()
  order by s.created_at desc
  limit 50
$$;
revoke all on function public.my_inbox() from public, anon;
grant execute on function public.my_inbox() to authenticated;

create or replace function public.mark_inbox_seen()
returns void language sql security definer set search_path = public, pg_temp as $$
  update public.song_shares set seen = true where to_user = auth.uid() and not seen
$$;
revoke all on function public.mark_inbox_seen() from public, anon;
grant execute on function public.mark_inbox_seen() to authenticated;


-- Cambiar el código de invitación (si se filtró). Solo el dueño.
create or replace function public.rotate_invite(pid uuid)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare c text;
begin
  update public.shared_playlists set invite_code = upper(encode(gen_random_bytes(6), 'hex'))
    where id = pid and owner = auth.uid() returning invite_code into c;
  if c is null then raise exception 'Solo quien creó la lista puede cambiar el código'; end if;
  return c;
end $$;
revoke all on function public.rotate_invite(uuid) from public, anon;
grant execute on function public.rotate_invite(uuid) to authenticated;

-- Agregar una canción a una lista: solo miembros, con límites.
create or replace function public.add_playlist_item(pid uuid, song_title text, song_artist text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_playlist_member(pid) then raise exception 'No eres parte de esa lista'; end if;
  -- Candado por usuario: las solicitudes simultáneas esperan su turno (los límites no se pueden saltar).
  perform pg_advisory_xact_lock(hashtextextended('item:' || auth.uid()::text, 0));

  if song_title is null or char_length(trim(song_title)) not between 1 and 200
     or char_length(coalesce(song_artist, '')) > 200 then
    raise exception 'Canción no válida';
  end if;
  if (select count(*) from public.playlist_items where playlist_id = pid) >= 500 then
    raise exception 'La lista llegó a 500 canciones';
  end if;
  if (select count(*) from public.playlist_items
      where added_by = auth.uid() and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'Agregaste muchas canciones seguidas. Espera un rato.';
  end if;
  insert into public.playlist_items (playlist_id, added_by, added_by_name, title, artist)
  values (pid, auth.uid(),
          (select display_name from public.social_profiles where user_id = auth.uid()),
          trim(song_title), nullif(trim(coalesce(song_artist, '')), ''));
end $$;
revoke all on function public.add_playlist_item(uuid, text, text) from public, anon;
grant execute on function public.add_playlist_item(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------- Contactos
-- Agregar a alguien por su código crea un contacto. Solo se pueden enviar
-- canciones cuando los dos se agregaron (amistad mutua). Quitar el contacto
-- corta los envíos de inmediato.
create table if not exists public.contacts (
  user_id uuid not null references auth.users (id) on delete cascade,
  contact_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, contact_id),
  check (user_id <> contact_id)
);
alter table public.contacts enable row level security;
drop policy if exists "ver mis contactos" on public.contacts;
create policy "ver mis contactos" on public.contacts
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "quitar contactos" on public.contacts;
create policy "quitar contactos" on public.contacts
  for delete to authenticated using (user_id = auth.uid());

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.contacts where user_id = a and contact_id = b)
     and exists (select 1 from public.contacts where user_id = b and contact_id = a)
$$;
revoke all on function public.are_friends(uuid, uuid) from public, anon, authenticated;

create or replace function public.add_contact(code text)
returns table (user_id uuid, display_name text, mutual boolean)
language plpgsql security definer set search_path = public, pg_temp as $$
declare other uuid; n int;
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  select p.user_id into other from public.social_profiles p where p.friend_code = upper(trim(code));
  if other is null then raise exception 'No encontré ese código'; end if;
  if other = auth.uid() then raise exception 'Ese es tu propio código'; end if;
  -- Candado por usuario: las solicitudes simultáneas esperan su turno (los límites no se pueden saltar).
  perform pg_advisory_xact_lock(hashtextextended('contact:' || auth.uid()::text, 0));
  select count(*) into n from public.contacts c where c.user_id = auth.uid();
  if n >= 200 then raise exception 'Llegaste al máximo de 200 amigos'; end if;
  insert into public.contacts (user_id, contact_id) values (auth.uid(), other) on conflict do nothing;
  return query
    select p.user_id, p.display_name, public.are_friends(auth.uid(), other)
    from public.social_profiles p where p.user_id = other;
end $$;
revoke all on function public.add_contact(text) from public, anon;
grant execute on function public.add_contact(text) to authenticated;

create or replace function public.my_contacts()
returns table (user_id uuid, display_name text, friend_code text, top_artists jsonb, mutual boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select p.user_id, p.display_name, p.friend_code,
         case when public.are_friends(auth.uid(), p.user_id) then p.top_artists else '[]'::jsonb end,
         public.are_friends(auth.uid(), p.user_id)
  from public.contacts c join public.social_profiles p on p.user_id = c.contact_id
  where c.user_id = auth.uid()
  order by p.display_name
$$;
revoke all on function public.my_contacts() from public, anon;
grant execute on function public.my_contacts() to authenticated;

-- Enviar una canción: solo a amigos mutuos y con límites contra spam.
create or replace function public.send_song(to_id uuid, song_title text, song_artist text, note text, is_anonymous boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  -- Candado por usuario: las solicitudes simultáneas esperan su turno (los límites no se pueden saltar).
  perform pg_advisory_xact_lock(hashtextextended('send:' || auth.uid()::text, 0));
  if not public.are_friends(auth.uid(), to_id) then
    raise exception 'Solo puedes enviar a amigos que también te agregaron';
  end if;
  if song_title is null or char_length(trim(song_title)) not between 1 and 200
     or char_length(coalesce(song_artist, '')) > 200 or char_length(coalesce(note, '')) > 200 then
    raise exception 'Canción o mensaje no válido';
  end if;
  if (select count(*) from public.song_shares
      where from_user = auth.uid() and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Enviaste muchas canciones. Espera un rato.';
  end if;
  if (select count(*) from public.song_shares
      where from_user = auth.uid() and to_user = to_id and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Ya le enviaste varias canciones a esta persona. Espera un rato.';
  end if;
  if exists (select 1 from public.song_shares
             where from_user = auth.uid() and to_user = to_id
               and lower(title) = lower(trim(song_title)) and created_at > now() - interval '1 day') then
    raise exception 'Ya le enviaste esa canción hoy';
  end if;
  insert into public.song_shares (from_user, to_user, anonymous, title, artist, message)
  values (auth.uid(), to_id, coalesce(is_anonymous, false), trim(song_title),
          nullif(trim(coalesce(song_artist, '')), ''), nullif(trim(coalesce(note, '')), ''));
end $$;
revoke all on function public.send_song(uuid, text, text, text, boolean) from public, anon;
grant execute on function public.send_song(uuid, text, text, text, boolean) to authenticated;

grant select, insert, update, delete on public.social_profiles to authenticated;
grant select, delete on public.shared_playlists, public.playlist_members, public.playlist_items to authenticated;
grant select on public.song_shares to authenticated;
grant select, delete on public.contacts to authenticated;
revoke insert, update on public.shared_playlists, public.playlist_members, public.playlist_items,
  public.song_shares, public.contacts, public.join_attempts from authenticated, anon;
revoke all on public.join_attempts from authenticated, anon;
-- Nadie modifica ni borra envíos desde la app (ni el remitente): solo se marcan vistos con mark_inbox_seen().
revoke update, delete on public.song_shares from authenticated, anon;
-- Sin cuenta no se toca ninguna tabla social.
revoke all on public.social_profiles, public.shared_playlists, public.playlist_members,
  public.playlist_items, public.song_shares, public.contacts from anon;
grant usage, select on all sequences in schema public to authenticated;

-- =============================================================================
-- Funciones sociales avanzadas (PR #20): escucha sincronizada, votos y tendencias.
-- Mismas reglas: todo por funciones que validan, candado por usuario y RLS.
-- =============================================================================

-- ------------------------------------------------------- Escucha sincronizada
-- Una «sala» por anfitrión. El anfitrión publica qué suena y en qué segundo;
-- los invitados (solo amigos mutuos con el código) ponen lo mismo en SU app.
create table if not exists public.listen_rooms (
  id uuid primary key default gen_random_uuid(),
  host uuid not null unique references auth.users (id) on delete cascade,
  code text not null unique default upper(encode(gen_random_bytes(4), 'hex')),
  title text check (char_length(title) <= 200),
  artist text check (char_length(artist) <= 200),
  position_ms integer not null default 0 check (position_ms >= 0),
  playing boolean not null default false,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create table if not exists public.room_members (
  room_id uuid not null references public.listen_rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
alter table public.listen_rooms enable row level security;
alter table public.room_members enable row level security;

create or replace function public.is_room_member(rid uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.room_members m where m.room_id = rid and m.user_id = auth.uid())
     or exists (select 1 from public.listen_rooms r where r.id = rid and r.host = auth.uid())
$$;
revoke all on function public.is_room_member(uuid) from public, anon;
grant execute on function public.is_room_member(uuid) to authenticated;

drop policy if exists "ver mi sala" on public.listen_rooms;
create policy "ver mi sala" on public.listen_rooms
  for select to authenticated using (public.is_room_member(id));
drop policy if exists "ver miembros de mi sala" on public.room_members;
create policy "ver miembros de mi sala" on public.room_members
  for select to authenticated using (public.is_room_member(room_id));
drop policy if exists "salir de una sala" on public.room_members;
create policy "salir de una sala" on public.room_members
  for delete to authenticated using (user_id = auth.uid());

-- Abrir (o reabrir) mi sala.
create or replace function public.open_room()
returns public.listen_rooms language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.listen_rooms;
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  perform pg_advisory_xact_lock(hashtextextended('room:' || auth.uid()::text, 0));
  select * into r from public.listen_rooms where host = auth.uid();
  if r.id is null then
    insert into public.listen_rooms (host) values (auth.uid()) returning * into r;
  end if;
  return r;
end $$;
revoke all on function public.open_room() from public, anon;
grant execute on function public.open_room() to authenticated;

-- El anfitrión publica lo que suena (máx. 1 vez por segundo).
create or replace function public.update_room(song_title text, song_artist text, pos integer, is_playing boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  if char_length(coalesce(song_title, '')) > 200 or char_length(coalesce(song_artist, '')) > 200
     or coalesce(pos, 0) < 0 or coalesce(pos, 0) > 86400000 then
    raise exception 'Datos no válidos';
  end if;
  update public.listen_rooms
     set title = nullif(trim(coalesce(song_title, '')), ''), artist = nullif(trim(coalesce(song_artist, '')), ''),
         position_ms = coalesce(pos, 0), playing = coalesce(is_playing, false), updated_at = now()
   where host = auth.uid() and updated_at < now() - interval '1 second';
end $$;
revoke all on function public.update_room(text, text, integer, boolean) from public, anon;
grant execute on function public.update_room(text, text, integer, boolean) to authenticated;

-- Unirse: código + ser amigo mutuo del anfitrión. Comparte el freno de intentos.
create or replace function public.join_room(room_code text)
returns public.listen_rooms language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.listen_rooms; fails int; members int;
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  perform pg_advisory_xact_lock(hashtextextended('join:' || auth.uid()::text, 0));
  select count(*) into fails from public.join_attempts
    where user_id = auth.uid() and not ok and at > now() - interval '1 hour';
  if fails >= 10 then raise exception 'Demasiados intentos. Prueba en una hora.'; end if;
  select * into r from public.listen_rooms where code = upper(trim(coalesce(room_code, '')));
  if r.id is null or not public.are_friends(auth.uid(), r.host) then
    insert into public.join_attempts (user_id, ok) values (auth.uid(), false);
    return null; -- «Código no válido» (no revela si existe)
  end if;
  if r.host = auth.uid() then return r; end if;
  select count(*) into members from public.room_members where room_id = r.id;
  if members >= 20 then raise exception 'La sala está llena (20 personas).'; end if;
  insert into public.join_attempts (user_id, ok) values (auth.uid(), true);
  insert into public.room_members (room_id, user_id) values (r.id, auth.uid()) on conflict do nothing;
  return r;
end $$;
revoke all on function public.join_room(text) from public, anon;
grant execute on function public.join_room(text) to authenticated;

-- Cerrar mi sala (saca a todos).
create or replace function public.close_room()
returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.listen_rooms where host = auth.uid()
$$;
revoke all on function public.close_room() from public, anon;
grant execute on function public.close_room() to authenticated;

-- ------------------------------------------------------------- Votación grupal
create table if not exists public.playlist_votes (
  item_id bigint not null references public.playlist_items (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  value smallint not null check (value in (-1, 1)),
  primary key (item_id, user_id)
);
alter table public.playlist_votes enable row level security; -- sin políticas: solo por funciones

-- Votar 👍 (1), 👎 (-1) o quitar el voto (0). Solo miembros de la lista.
create or replace function public.vote_item(item bigint, vote smallint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare pid uuid;
begin
  select playlist_id into pid from public.playlist_items where id = item;
  if pid is null or not public.is_playlist_member(pid) then raise exception 'No eres parte de esa lista'; end if;
  if vote not in (-1, 0, 1) then raise exception 'Voto no válido'; end if;
  if vote = 0 then
    delete from public.playlist_votes where item_id = item and user_id = auth.uid();
  else
    insert into public.playlist_votes (item_id, user_id, value) values (item, auth.uid(), vote)
      on conflict (item_id, user_id) do update set value = excluded.value;
  end if;
end $$;
revoke all on function public.vote_item(bigint, smallint) from public, anon;
grant execute on function public.vote_item(bigint, smallint) to authenticated;

-- Puntaje de cada canción de una lista (y mi voto). Los votos de cada quien no se exponen.
create or replace function public.playlist_scores(pid uuid)
returns table (item_id bigint, score integer, my_vote smallint)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_playlist_member(pid) then raise exception 'No eres parte de esa lista'; end if;
  return query
    select i.id, coalesce(sum(v.value), 0)::integer,
           coalesce(max(case when v.user_id = auth.uid() then v.value end), 0)::smallint
    from public.playlist_items i
    left join public.playlist_votes v on v.item_id = i.id
    where i.playlist_id = pid
    group by i.id;
end $$;
revoke all on function public.playlist_scores(uuid) from public, anon;
grant execute on function public.playlist_scores(uuid) to authenticated;

-- ------------------------------------------------------ Tendencias de tu círculo
-- Artistas favoritos que comparten 2 o más de tus amigos mutuos. Nunca dice
-- quién: solo cuántos (y solo si son al menos 2, para que no se pueda deducir).
create or replace function public.circle_trends()
returns table (artist text, friends integer)
language sql stable security definer set search_path = public, pg_temp as $$
  select a.artist, count(distinct p.user_id)::integer
  from public.contacts c
  join public.social_profiles p on p.user_id = c.contact_id
  cross join lateral jsonb_array_elements_text(p.top_artists) as a(artist)
  where c.user_id = auth.uid() and public.are_friends(auth.uid(), c.contact_id)
  group by a.artist
  having count(distinct p.user_id) >= 2
  order by 2 desc, 1
  limit 10
$$;
revoke all on function public.circle_trends() from public, anon;
grant execute on function public.circle_trends() to authenticated;

grant select, delete on public.listen_rooms, public.room_members to authenticated;
revoke insert, update on public.listen_rooms, public.room_members from authenticated, anon;
revoke all on public.playlist_votes from authenticated, anon;
revoke all on public.listen_rooms, public.room_members from anon;
