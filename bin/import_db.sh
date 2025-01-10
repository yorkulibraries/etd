#!/bin/bash
dump=$1

[ -f "$dump" ] &&  zcat -f "$dump" | grep 'DROP TABLE ' > drop.sql 
[ -f "$dump" ] &&  zcat -f "$dump" | sed '/DROP DATABASE \|CREATE DATABASE \|USE `/d'  | sed 's/ datetime / datetime(6) /'  > import.sql 

cat drop.sql | rails db -p
cat import.sql | rails db -p

rails db:migrate
