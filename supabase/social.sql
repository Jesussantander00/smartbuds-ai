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
  if code is null or char_length(trim(code)) not between 6 and 16 then raise exception 'Código no válido'; end if;
  select count(*) into fails from public.join_attempts
    where user_id = auth.uid() and not ok and at > now() - interval '1 hour';
  if fails >= 10 then raise exception 'Demasiados intentos. Prueba en una hora.'; end if;
  select * into p from public.shared_playlists where invite_code = upper(trim(code));
  if p.id is null then
    insert into public.join_attempts (user_id, ok) values (auth.uid(), false);
    raise exception 'Código no válido';
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
grant usage, select on all sequences in schema public to authenticated;
