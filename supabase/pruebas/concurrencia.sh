#!/usr/bin/env bash
# 30 envíos simultáneos x 5 rondas: nunca debe guardar más de 5 (límite por persona).
P="psql -h /tmp/pg -p 5499 -U postgres -d t -q -t -A"
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222
for round in 1 2 3 4 5; do
  $P -c "delete from song_shares;" >/dev/null
  for i in $(seq 1 30); do
    $P -c "set role authenticated; set request.jwt.claim.sub='$A'; select send_song('$B','R$round C$i','X',null,false);" >/dev/null 2>&1 &
  done
  wait
  echo "ronda $round: $($P -c "select count(*) from song_shares;") guardados (máx. 5)"
done
