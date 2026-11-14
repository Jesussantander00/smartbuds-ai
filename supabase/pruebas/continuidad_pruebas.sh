#!/usr/bin/env bash
# Pruebas de supabase/continuidad.sql en un Postgres local (puerto 5499).
D="$(dirname "$0")"
psql -h /tmp/pg -p 5499 -U postgres -q -c "drop database if exists c;" -c "create database c;" 2>/dev/null
P="psql -h /tmp/pg -p 5499 -U postgres -q -v ON_ERROR_STOP=1 -d c"
$P -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if; if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if; end \$\$;"
$P -f "$D/auth_simulado.sql" && $P -f "$D/../dispositivos.sql" 2>&1 | grep -v NOTICE
$P -f "$D/../continuidad.sql" 2>&1 | grep -v NOTICE; $P -f "$D/../continuidad.sql" 2>&1 | grep -v NOTICE; echo "idempotente ok"
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222
as(){ u=$1; shift; psql -h /tmp/pg -p 5499 -U postgres -d c -q -t -A -c "set role authenticated; set request.jwt.claim.sub='$u'; $*" 2>&1 | sed 's/^/   /'; }
an(){ psql -h /tmp/pg -p 5499 -U postgres -d c -q -t -A -c "set role anon; $*" 2>&1 | sed 's/^/   /'; }
echo "1 publicar con cola, ambiente y perfil:"; as $A "select upsert_my_device2('aaaaaaaaaaaaaaaa','Tel','android','Ojalá','Ryan Castro','Spotify',true,'[\"Una\",\"Dos\"]','entrenar','estudio'); select queue, mood, usage from user_devices;"
echo "2 la función vieja sigue funcionando:"; as $A "select upsert_my_device('bbbbbbbbbbbbbbbb','Tab','android',null,null,null,false); select queue from user_devices where device_id='bbbbbbbbbbbbbbbb';"
echo "3 cola de 30 -> se guardan 20:"; as $A "select upsert_my_device2('aaaaaaaaaaaaaaaa','Tel','android',null,null,null,true,(select jsonb_agg(i::text) from generate_series(1,30) i),null,null); select jsonb_array_length(queue) from user_devices where device_id='aaaaaaaaaaaaaaaa';"
echo "4 elementos no-texto se descartan:"; as $A "select upsert_my_device2('aaaaaaaaaaaaaaaa','Tel','android',null,null,null,true,'[1,{\"x\":1},\"ok\"]',null,null); select queue from user_devices where device_id='aaaaaaaaaaaaaaaa';"
echo "5 cola no-arreglo -> vacía:"; as $A "select upsert_my_device2('aaaaaaaaaaaaaaaa','Tel','android',null,null,null,true,'{\"a\":1}',null,null); select queue from user_devices where device_id='aaaaaaaaaaaaaaaa';"
echo "6 textos largos se recortan (200):"; as $A "select upsert_my_device2('aaaaaaaaaaaaaaaa','Tel','android',null,null,null,true,jsonb_build_array(repeat('x',500)),repeat('m',100),repeat('u',100)); select length(queue->>0), length(mood), length(usage) from user_devices where device_id='aaaaaaaaaaaaaaaa';"
echo "7 B no ve la cola de A (0):"; as $B "select count(*) from user_devices;"
echo "8 anon no puede:"; an "select upsert_my_device2('cccccccccccccccc','x','android',null,null,null,false,'[]',null,null);"
echo "9 escritura directa bloqueada:"; as $A "update user_devices set queue='[\"hack\"]';"
echo "10 límite de 10 sigue:"; for i in $(seq 1 12); do as $B "select upsert_my_device2(lpad('$i',16,'d'),'D','android',null,null,null,false,'[]',null,null);" >/dev/null; done; as $B "select count(*) from user_devices;"
