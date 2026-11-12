#!/usr/bin/env bash
# Prueba de funciones sociales avanzadas (sala, votos, tendencias) con 3 cuentas.
P="psql -h /tmp/pg -p 5499 -U postgres -d t -q -t -A"
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222; C=33333333-3333-3333-3333-333333333333
ok=0; bad=0
as() { local u=$1; shift; $P -c "set role authenticated; set request.jwt.claim.sub='$u'; $*" 2>&1; }
expect_ok()  { local out; out=$(as "$@"); if echo "$out" | grep -q ERROR; then echo "  ✗ FALLÓ: ${2:0:80} → $out"; bad=$((bad+1)); else echo "  ✓ permitido: ${2:0:70}"; ok=$((ok+1)); fi; }
expect_err() { local out; out=$(as "$@"); if echo "$out" | grep -q ERROR; then echo "  ✓ bloqueado: ${2:0:70}"; ok=$((ok+1)); else echo "  ✗ NO SE BLOQUEÓ: ${2:0:80} → $out"; bad=$((bad+1)); fi; }
expect_val() { local want=$1; shift; local out; out=$(as "$@"); if [ "$out" = "$want" ]; then echo "  ✓ ${2:0:60} = $want"; ok=$((ok+1)); else echo "  ✗ ${2:0:80}: esperaba «$want», obtuvo «$out»"; bad=$((bad+1)); fi; }

echo "Escucha sincronizada"
CODE=$(as $A "select code from open_room();")
expect_val "$CODE" $A "select code from open_room();"   # reabrir devuelve la misma
sleep 1.1
expect_ok  $A "select update_room('Tusa','Karol G',42000,true);"
expect_val "" $C "select coalesce(id::text,'') from join_room('$CODE');"   # C no es amigo de A
expect_val "0" $C "select count(*) from listen_rooms;"
expect_ok  $B "select id from join_room('$CODE');"                          # B es amigo mutuo
expect_val "Tusa|42000|true" $B "select title||'|'||position_ms||'|'||playing from listen_rooms;"
expect_ok  $B "select update_room('Hack','X',1,true);"                      # no falla, pero no cambia nada
expect_val "Tusa" $B "select title from listen_rooms;"
expect_err $B "update listen_rooms set title='hack';"
expect_err $B "insert into room_members values ((select id from listen_rooms limit 1), '$C');"
expect_val "1" $A "select count(*) from room_members;"
expect_ok  $A "select update_room('Ojala','Ryan Castro',0,true);"   # menos de 1 s después: se ignora
expect_val "Tusa" $B "select title from listen_rooms;"
sleep 1.1
expect_ok  $A "select update_room('Ojala','Ryan Castro',0,true);"
expect_val "Ojala" $B "select title from listen_rooms;"
expect_err $A "select update_room(repeat('x',300),'a',0,true);"
expect_ok  $A "select close_room();"
expect_val "0" $B "select count(*) from listen_rooms;"

echo "Votación"
PCODE=$(as $A "select invite_code from create_playlist('Fiesta');")
PID=$(as $A "select id from shared_playlists where name='Fiesta';")
as $A "select add_playlist_item('$PID','Provenza','Karol G');" >/dev/null
as $A "select add_playlist_item('$PID','Tusa','Karol G');" >/dev/null
as $B "select join_playlist('$PCODE');" >/dev/null
I1=$(as $A "select id from playlist_items where title='Provenza';")
expect_ok  $A "select vote_item($I1, 1::smallint);"
expect_ok  $B "select vote_item($I1, 1::smallint);"
expect_ok  $B "select vote_item($I1, 1::smallint);"   # repetir no suma doble
expect_val "2" $A "select score from playlist_scores('$PID') where item_id=$I1;"
expect_ok  $B "select vote_item($I1, (-1)::smallint);" # cambiar el voto
expect_val "0|-1" $B "select score||'|'||my_vote from playlist_scores('$PID') where item_id=$I1;"
expect_err $C "select vote_item($I1, 1::smallint);"
expect_err $C "select * from playlist_scores('$PID');"
expect_err $B "select * from playlist_votes;"
expect_err $B "insert into playlist_votes values ($I1,'$B',1);"
expect_err $B "select vote_item($I1, 5::smallint);"

echo "Tendencias del círculo (solo con 2+ amigos, sin decir quién)"
$P -c "update social_profiles set top_artists='[\"Karol G\",\"Feid\"]' where user_id='$B'; update social_profiles set top_artists='[\"Karol G\",\"Shakira\"]' where user_id='$C'; insert into contacts values ('$A','$C'),('$C','$A') on conflict do nothing;" >/dev/null
expect_val "Karol G|2" $A "select artist||'|'||friends from circle_trends();"
expect_val "0" $B "select count(*) from circle_trends();"    # B solo tiene 1 amigo mutuo
$P -c "delete from contacts where user_id='$C' and contact_id='$A';" >/dev/null
expect_val "0" $A "select count(*) from circle_trends();"   # C quitó a A: ya no cuenta

echo "anon"
for q in "select * from open_room();" "select * from circle_trends();" "select * from listen_rooms;" "select vote_item(1,1::smallint);"; do
  out=$($P -c "set role anon; $q" 2>&1); if echo "$out" | grep -q ERROR; then echo "  ✓ anon bloqueado: $q"; ok=$((ok+1)); else echo "  ✗ anon: $q → $out"; bad=$((bad+1)); fi
done
echo; echo "RESULTADO: $ok correctos, $bad fallos"
