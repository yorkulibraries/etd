#!/usr/bin/env bash

cd /app && RAILS_ENV=test DATABASE_URL=sqlite3:db/test.sqlite3 rails test $@

