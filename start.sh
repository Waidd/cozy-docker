#!/bin/bash

# Check if CouchDB is running
curl --output /dev/null --silent --head --fail --retry 5 --retry-delay 5 couchdb:5984 || { echo  "CouchDB is NOT running"; exit 1; }
echo "CouchDB is up and running"

# start postfix
postfix start

# generate login/password token for couchdb and set them if they does not exists
if [ ! -f /etc/cozy/couchdb.login ]; then
  echo "Generate couchdb.login"
  echo `cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1` > /etc/cozy/couchdb.login
  echo `cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1` >> /etc/cozy/couchdb.login
  chown cozy-data-system /etc/cozy/couchdb.login
  chmod 640 /etc/cozy/couchdb.login

  if curl -s -X PUT couchdb:5984/_config/admins/$(head -n1 /etc/cozy/couchdb.login) -d "\"$(tail -n1 /etc/cozy/couchdb.login)\"" > /dev/null; then
    echo "CouchDB credentials setted"
  else
    echo "Cannot set CouchDB user"
    exit 1
  fi
else
  echo "Use existing couchdb.login"
fi

# generate controller token if it does not exist
if [ ! -f /etc/cozy/controller.token ]; then
  echo "Generate controller.token"
  echo `cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1` > /etc/cozy/controller.token
  chown cozy-home /etc/cozy/controller.token
  chmod 700 /etc/cozy/controller.token
else
  echo "Use existing controller.token"
fi

# @TODO redirect log to a file ?
# start cozy-controller
node server.js &
SERVER_PID=$!

# wait for cozy-controller to listen 9002
until $(curl --output /dev/null --silent --head --fail localhost:9002); do
  # check if cozy-controller is still running
  if ! ps -p $SERVER_PID > /dev/null; then
    echo "Cozy-controller has crashed"
    exit 1
  fi
  printf '.'
  sleep 1
done

# install/reinstall main packages
cozy-monitor start data-system
cozy-monitor start home
cozy-monitor start proxy

# reinstall missing app in the case of a relocation
cozy-monitor reinstall-missing-app

# check host if defined in env
if [ -n "$COZY_HOST" ]; then
  coffee /usr/local/cozy/apps/home/commands.coffee setdomain $COZY_HOST
fi

wait $SERVER_PID
