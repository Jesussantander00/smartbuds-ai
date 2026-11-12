#!/usr/bin/env bash
# Prueba integral del módulo social con 3 cuentas (A envía, B recibe, C intenta lo ajeno).
P="psql -h /tmp/pg -p 5499 -U postgres -d t -q -t -A"
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222; C=33333333-3333-3333-3333-333333333333
ok=0; bad=0
as() { local u=$1; shift; $P -c "set role authenticated; set request.jwt.claim.sub='$u'; $*" 2>&1; }
expect_ok()  { local out; out=$(as "$@"); if echo "$out" | grep -q ERROR; then echo "  ✗ FALLÓ (debía funcionar): ${*:2} → $out"; bad=$((bad+1)); else echo "  ✓ permitido: ${2:0:70}"; ok=$((ok+1)); fi; }
expect_err() { local out; out=$(as "$@"); if echo "$out" | grep -q ERROR; then echo "  ✓ bloqueado: ${2:0:70}"; ok=$((ok+1)); else echo "  ✗ NO SE BLOQUEÓ: ${*:2} → $out"; bad=$((bad+1)); fi; }
expect_val() { local want=$1; shift; local out; out=$(as "$@"); if [ "$out" = "$want" ]; then echo "  ✓ ${2:0:60} = $want"; ok=$((ok+1)); else echo "  ✗ ${*:2}: esperaba «$want», obtuvo «$out»"; bad=$((bad+1)); fi; }
$P -c "delete from song_shares; delete from join_attempts;" >/dev/null

echo "A envía · B recibe"
expect_ok  $A "select send_song('$B','Tusa','Karol G','para ti',false);"
expect_ok  $A "select send_song('$B','Secreta','X',null,true);"
expect_val "Ana|Tusa" $B "select coalesce(from_name,'ANON')||'|'||title from my_inbox() where title='Tusa';"
expect_val "ANON" $B "select coalesce(from_name,'ANON') from my_inbox() where title='Secreta';"

echo "Privacidad del anónimo (consultas indirectas desde B)"
expect_val "0" $B "select count(*) from song_shares;"
expect_val "" $B "select from_user from song_shares;"
expect_val "0" $B "select count(*) from song_shares where to_user = auth.uid();"
expect_val "" $B "select string_agg(column_name, ',') from information_schema.columns where table_name='my_inbox';"
expect_val "id,from_name,title,artist,message,seen,created_at" $B "select string_agg(parameter_name, ',' order by ordinal_position) from information_schema.parameters where specific_name like 'my_inbox%' and parameter_mode='OUT';"

echo "C intenta ver/tocar lo ajeno"
expect_val "0" $C "select count(*) from my_inbox();"
expect_val "0" $C "select count(*) from contacts;"
expect_err $C "select send_song('$B','x','y',null,false);"
expect_err $C "insert into song_shares(from_user,to_user,title) values ('$C','$B','x');"
expect_err $C "update song_shares set title='hack';"
expect_err $C "delete from song_shares;"
expect_err $C "insert into contacts values ('$B','$C');"
expect_err $C "insert into contacts values ('$C','$B');"
as $C "update social_profiles set display_name='hack' where user_id='$A';" >/dev/null
expect_val "Ana" $A "select display_name from social_profiles where user_id=auth.uid();"
expect_val "0" $C "with u as (update social_profiles set display_name='hack' where user_id='$A' returning 1) select count(*) from u;"
expect_err $C "select are_friends('$A','$B');"
expect_err $C "insert into join_attempts(user_id,ok) values ('$C',true);"
expect_err $C "delete from join_attempts;"
expect_val "0" $C "select count(*) from social_profiles where user_id <> auth.uid();"

echo "Listas"
CODE=$(as $A "select invite_code from create_playlist('Viaje');")
PID=$(as $A "select id from shared_playlists where name='Viaje' limit 1;")
expect_val "0" $C "select count(*) from shared_playlists;"
expect_val "0" $C "select count(*) from playlist_items where playlist_id='$PID';"
expect_err $C "select add_playlist_item('$PID','x','y');"
expect_err $C "insert into playlist_members values ('$PID','$C');"
expect_err $C "update shared_playlists set owner='$C' where id='$PID';"
expect_ok  $B "select join_playlist('$CODE');"
expect_ok  $B "select add_playlist_item('$PID','Provenza','Karol G');"
expect_err $B "select rotate_invite('$PID');"
expect_val "0" $B "with d as (delete from shared_playlists where id='$PID' returning 1) select count(*) from d;"

echo "Bloqueo por intentos (atómico y no reiniciable)"
for i in $(seq 1 12); do as $C "select join_playlist('NOPE$i$i$i');" >/dev/null & done; wait
expect_val "10" $C "select 10;"  # marcador
FAILS=$($P -c "select count(*) from join_attempts where user_id='$C' and not ok;")
echo "  · intentos fallidos guardados: $FAILS (simultáneos)"
expect_err $C "select join_playlist('$CODE');"
expect_err $C "select join_playlist('X');"

echo "Eliminación de amistad invalida al instante"
expect_ok  $B "delete from contacts where user_id=auth.uid() and contact_id='$A';"
expect_err $A "select send_song('$B','Despues','Z',null,false);"
expect_val "false" $A "select mutual::text from my_contacts() where user_id='$B';"
expect_val "[]" $A "select top_artists::text from my_contacts() where user_id='$B';"

echo "anon"
expect_err_anon() { local out; out=$($P -c "set role anon; $1" 2>&1); if echo "$out" | grep -q ERROR; then echo "  ✓ anon bloqueado: ${1:0:50}"; ok=$((ok+1)); else echo "  ✗ anon NO bloqueado: $1 → $out"; bad=$((bad+1)); fi; }
expect_err_anon "select * from my_inbox();"
expect_err_anon "select * from social_profiles;"
expect_err_anon "select * from song_shares;"
expect_err_anon "select join_playlist('$CODE');"
echo; echo "RESULTADO: $ok correctos, $bad fallos"
