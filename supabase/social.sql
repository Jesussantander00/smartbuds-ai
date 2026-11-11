-- SmartBuds AI · Funciones sociales (ejecutar después de schema.sql, cuentas.sql y seguridad.sql).
-- Todo requiere cuenta. Nadie ve el historial de nadie: solo lo que cada quien
-- decide compartir (perfil público opcional, listas compartidas y canciones enviadas).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- Perfil público
-- Opcional: nombre visible, código de amigo y artistas favoritos (nunca el historial).
create table if not exists public.social_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  friend_code text not null unique,
  top_artists jsonb not null default '[]'::jsonb,
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
create or replace function public.profile_by_code(code text)
returns table (user_id uuid, display_name text, top_artists jsonb)
language sql stable security definer set search_path = public as $$
  select p.user_id, p.display_name, p.top_artists
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
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
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
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.playlist_members m where m.playlist_id = pid and m.user_id = auth.uid())
$$;
revoke all on function public.is_playlist_member(uuid) from public, anon;
grant execute on function public.is_playlist_member(uuid) to authenticated;

drop policy if exists "ver mis listas" on public.shared_playlists;
create policy "ver mis listas" on public.shared_playlists
  for select to authenticated using (owner = auth.uid() or public.is_playlist_member(id));
drop policy if exists "crear listas" on public.shared_playlists;
create policy "crear listas" on public.shared_playlists
  for insert to authenticated with check (owner = auth.uid());
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
create policy "agregar a mis listas" on public.playlist_items
  for insert to authenticated with check (added_by = auth.uid() and public.is_playlist_member(playlist_id));
drop policy if exists "quitar lo que agregué" on public.playlist_items;
create policy "quitar lo que agregué" on public.playlist_items
  for delete to authenticated using (added_by = auth.uid());

-- Crear una lista y quedar como miembro.
create or replace function public.create_playlist(list_name text)
returns public.shared_playlists language plpgsql security definer set search_path = public as $$
declare p public.shared_playlists;
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  insert into public.shared_playlists (owner, name) values (auth.uid(), trim(list_name)) returning * into p;
  insert into public.playlist_members (playlist_id, user_id) values (p.id, auth.uid());
  return p;
end $$;
revoke all on function public.create_playlist(text) from public, anon;
grant execute on function public.create_playlist(text) to authenticated;

-- Unirse con el código de invitación.
create or replace function public.join_playlist(code text)
returns public.shared_playlists language plpgsql security definer set search_path = public as $$
declare p public.shared_playlists;
begin
  if auth.uid() is null then raise exception 'Necesitas una cuenta'; end if;
  select * into p from public.shared_playlists where invite_code = upper(trim(code));
  if p.id is null then raise exception 'Código no válido'; end if;
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
create policy "enviar canciones" on public.song_shares
  for insert to authenticated with check (from_user = auth.uid() and to_user <> auth.uid());
drop policy if exists "ver lo que envié" on public.song_shares;
create policy "ver lo que envié" on public.song_shares
  for select to authenticated using (from_user = auth.uid());
-- El que recibe NO lee la tabla directo (vería quién la mandó aunque sea anónima):
-- usa my_inbox(), que oculta al remitente cuando es anónimo.

create or replace function public.my_inbox()
returns table (id bigint, from_name text, title text, artist text, message text, seen boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
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
returns void language sql security definer set search_path = public as $$
  update public.song_shares set seen = true where to_user = auth.uid() and not seen
$$;
revoke all on function public.mark_inbox_seen() from public, anon;
grant execute on function public.mark_inbox_seen() to authenticated;

grant select, insert, update, delete on public.social_profiles to authenticated;
grant select, insert, delete on public.shared_playlists, public.playlist_members, public.playlist_items to authenticated;
grant select, insert on public.song_shares to authenticated;
grant usage, select on all sequences in schema public to authenticated;
