psql -h /tmp/pg -p 5499 -U postgres -q -c "drop database if exists b;" -c "create database b;"
P="psql -h /tmp/pg -p 5499 -U postgres -q -v ON_ERROR_STOP=1 -d b"
$P -f "$(dirname "$0")/auth_simulado.sql"
$P -f "$(dirname "$0")/../respaldo.sql" 2>&1 | grep -v NOTICE; $P -f "$(dirname "$0")/../respaldo.sql" 2>&1 | grep -v NOTICE; echo "idempotente ok"
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222
as(){ u=$1; shift; psql -h /tmp/pg -p 5499 -U postgres -d b -q -t -A -c "set role authenticated; set request.jwt.claim.sub='$u'; $*" 2>&1 | sed 's/^/   /'; }
an(){ psql -h /tmp/pg -p 5499 -U postgres -d b -q -t -A -c "set role anon; $*" 2>&1 | sed 's/^/   /'; }
echo "1 crear (upsert):"; as $A "insert into user_backups(user_id,device,data) values ('$A','Tel','{\"v\":2}') on conflict (user_id) do update set data=excluded.data, device=excluded.device; select device, data from user_backups;"
echo "2 actualizar:"; as $A "insert into user_backups(user_id,device,data) values ('$A','Tel2','{\"v\":3}') on conflict (user_id) do update set data=excluded.data, device=excluded.device; select device, data from user_backups;"
echo "3 B no ve la de A (0):"; as $B "select count(*) from user_backups;"
echo "4 B no puede escribir como A:"; as $B "insert into user_backups(user_id,data) values ('$A','{}');"
echo "5 B no cambia la de A (0 filas):"; as $B "update user_backups set data='{}' returning 1;"
echo "6 B no borra la de A:"; as $B "delete from user_backups;"; as $A "select count(*) from user_backups;"
echo "7 anon sin acceso:"; an "select * from user_backups;"
echo "8 no-objeto:"; as $A "update user_backups set data='[1]';"
echo "9 demasiado grande:"; as $A "update user_backups set data=jsonb_build_object('x',repeat('a',2100000));"
echo "10 fecha la pone el servidor:"; as $A "update user_backups set updated_at='2000-01-01'; select updated_at > now() - interval '1 minute' from user_backups;"
echo "11 cambiar user_id a otro:"; as $A "update user_backups set user_id='$B';"
echo "12 sin sesión:"; psql -h /tmp/pg -p 5499 -U postgres -d b -q -t -A -c "set role authenticated; insert into user_backups(data) values ('{}');" 2>&1 | sed 's/^/   /'
echo "13 borrar la propia:"; as $A "delete from user_backups; select count(*) from user_backups;"
echo "14 borrar cuenta borra la copia:"; as $A "insert into user_backups(user_id,data) values ('$A','{}');"; psql -h /tmp/pg -p 5499 -U postgres -d b -q -t -A -c "delete from auth.users where id='$A'; select count(*) from user_backups;"
