#!/usr/bin/env bash
# Crea la base «t» con un auth simulado (auth.users, auth.uid()) y 3 usuarios, y carga social.sql.
P="psql -h /tmp/pg -p 5499 -U postgres -q -v ON_ERROR_STOP=1"
psql -h /tmp/pg -p 5499 -U postgres -q -c "drop database if exists t;" -c "create database t;" 2>/dev/null
P="$P -d t"
$P -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if; if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if; end \$\$;"
$P -f "$(dirname "$0")/auth_simulado.sql"
$P -f "$(dirname "$0")/../social.sql" 2>&1 | grep -v NOTICE
A=11111111-1111-1111-1111-111111111111; B=22222222-2222-2222-2222-222222222222; C=33333333-3333-3333-3333-333333333333
$P -c "insert into social_profiles(user_id,display_name,friend_code) values ('$A','Ana','ANA222'),('$B','Beto','BETO22'),('$C','Caro','CARO22'); insert into contacts values ('$A','$B'),('$B','$A');"
