P="psql -h /tmp/pg -p 5499 -U postgres -q -v ON_ERROR_STOP=1"
psql -h /tmp/pg -p 5499 -U postgres -q -c "drop database if exists d;" -c "create database d;"
P="$P -d d"
$P -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if; if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if; end \$\$;"
$P -f "$(dirname "$0")/auth_simulado.sql" && $P -f /home/claude/sb-repo/supabase/dispositivos.sql 2>&1 | grep -v NOTICE
$P -f /home/claude/sb-repo/supabase/dispositivos.sql 2>&1 | grep -v NOTICE; echo "idempotent ok"
A=11111111-1111-1111-1111-111111111111; Bu=22222222-2222-2222-2222-222222222222
as(){ u=$1; shift; psql -h /tmp/pg -p 5499 -U postgres -d d -q -t -A -c "set role authenticated; set request.jwt.claim.sub='$u'; $*" 2>&1 | sed 's/^/   /'; }
an(){ psql -h /tmp/pg -p 5499 -U postgres -d d -q -t -A -c "set role anon; $*" 2>&1 | sed 's/^/   /'; }
echo "1 upsert:"; as $A "select upsert_my_device('aaaaaaaaaaaaaaaa','Mi Android','android','Ojalá','Ryan Castro','Spotify',true);"
echo "2 update:"; as $A "select upsert_my_device('aaaaaaaaaaaaaaaa','Mi Android','android','Otra','X','YT',false); select name,title,playing from user_devices;"
echo "3 B ve A? (0):"; as $Bu "select count(*) from user_devices;"
echo "4 B borra A (A sigue 1):"; as $Bu "delete from user_devices; " ; as $A "select count(*) from user_devices;"
echo "5 insert directo (denegado):"; as $A "insert into user_devices(user_id,device_id,name,platform) values ('$A','bbbbbbbbbbbbbbbb','x','android');"
echo "6 update directo (denegado):"; as $A "update user_devices set name='hack';"
echo "7 anon select (denegado):"; an "select * from user_devices;"
echo "8 anon rpc (denegado):"; an "select upsert_my_device('cccccccccccccccc','x','android',null,null,null,false);"
echo "9 bad id:"; as $A "select upsert_my_device('NOT-HEX','x','android',null,null,null,false);"
echo "10 bad platform:"; as $A "select upsert_my_device('dddddddddddddddd','x','windows',null,null,null,false);"
echo "11 empty name:"; as $A "select upsert_my_device('dddddddddddddddd','  ','android',null,null,null,false);"
echo "12 long title truncated (200):"; as $A "select upsert_my_device('aaaaaaaaaaaaaaaa','Mi Android','android',repeat('a',500),null,null,false); select length(title) from user_devices where device_id='aaaaaaaaaaaaaaaa';"
echo "13 limit 10:"; for i in $(seq 1 10); do as $A "select upsert_my_device(lpad('$i',16,'e'),'D$i','android',null,null,null,false);" >/dev/null; done; as $A "select count(*) from user_devices;"; as $A "select upsert_my_device('9999999999999999','x','android',null,null,null,false);"
echo "14 existing still updates at limit:"; as $A "select upsert_my_device('aaaaaaaaaaaaaaaa','Renamed','android',null,null,null,true); select name from user_devices where device_id='aaaaaaaaaaaaaaaa';"
echo "15 own delete (9):"; as $A "delete from user_devices where device_id=lpad('1',16,'e'); select count(*) from user_devices;"
echo "16 no uid:"; psql -h /tmp/pg -p 5499 -U postgres -d d -q -t -A -c "set role authenticated; select upsert_my_device('ffffffffffffffff','x','android',null,null,null,false);" 2>&1 | sed 's/^/   /'
echo "17 concurrencia (B, 15 en paralelo -> max 10):"
for i in $(seq 1 15); do psql -h /tmp/pg -p 5499 -U postgres -d d -q -t -A -c "set role authenticated; set request.jwt.claim.sub='$Bu'; select upsert_my_device(lpad('$i',16,'c'),'D','android',null,null,null,false);" >/dev/null 2>&1 & done; wait
as $Bu "select count(*) from user_devices;"
echo "18 user delete cascades:"; psql -h /tmp/pg -p 5499 -U postgres -d d -q -t -A -c "delete from auth.users where id='$Bu'; select count(*) from user_devices where user_id='$Bu';"
