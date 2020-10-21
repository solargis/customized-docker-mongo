#!/bin/bash
cd "$(dirname "$BASH_SOURCE")"
MONGO_TAG="${MONGO_TAG:-4.2}"
export IMAGE="solargis/mongo:${TAG:-$MONGO_TAG}"
export CONTAINER="test-mongo"

container() { echo -n "$@ "; docker "$@" "$CONTAINER"; }
wait-for() {
  local START="$(date +%s)"
  local STEP=0.3
  local MAX=30
  local MSG=Waiting...
  local EXIT=
  local DEBUG=
  local MACH_COUNT=
  local SUCCESS_COUNTER=0
  local FAIL_COUNTER=0
  local COUNT_STATE=
  while [ "${1:0:2}" == "--" ]; do case "${1/=*/}" in
  --max) MAX="${1/*=/}";;
  --step) STEP="${1/*=/}";;
  --msg) MSG="${1/*=/}";;
  --debug) DEBUG="${1/*=/}";;
  --min) MACH_COUNT="${1/*=/}";;
  --fail) EXIT="1";;
  esac; shift; done

  [ "$SUCCESS_COUNTER" -gt 0 ] && COUNT_STATE="\x1b[0;32m$SUCCESS_COUNTER\x1b[2m/$MACH_COUNT\x1b[31m/$FAIL_COUNTER" || COUNT_STATE="\x1b[0;31;2m$FAIL_COUNTER"
  echo -en "$MSG \x1b[s"
  while true; do
    echo -en "\x1b[u\x1b[0K$COUNT_STATE \x1b[0;33m$(($MAX - $(date +%s) + $START))s \x1b[0;2m(timeout)\x1b[0m "
    eval "$@" 2>/dev/null && SUCCESS_COUNTER=$(($SUCCESS_COUNTER + 1)) || FAIL_COUNTER=$(($FAIL_COUNTER + 1))
    [ $SUCCESS_COUNTER -gt 0 ] && COUNT_STATE="\x1b[0;32m$SUCCESS_COUNTER\x1b[2m${MACH_COUNT:+/$MACH_COUNT}\x1b[31m:$FAIL_COUNTER" || COUNT_STATE="\x1b[0;31;2m$FAIL_COUNTER"
    [ $SUCCESS_COUNTER -gt 0 ] && ( [ -z "$MACH_COUNT" ] || [ $SUCCESS_COUNTER -ge $MACH_COUNT ] ) && break
    if [ "$(( $(date +%s) - $START ))" -ge "$MAX" ]; then
      echo -e "\x1b[u\x1b[0K$COUNT_STATE \x1b[0;31mtimeout \x1b[2m($(($(date +%s) - $START))s)\x1b[0m"
      [ -z "$DEBUG" ] || eval "$DEBUG"
      [ -z "$EXIT" ] && return 1 || exit 1
    fi
    sleep 0.3
  done
  echo -e "\x1b[u\x1b[0K$COUNT_STATE \x1b[0;32m$(($(date +%s) - $START))s\x1b[0m"
}
inspect() { env PS1='\[\033[34m\]\w\[\033[00m\]:\[\033[33m\]inspect\[\033[00m\]$ ' bash --norc; }
_is_runing() { [ "$(docker ps "$@" | awk -v c="$CONTAINER" '$NF==c' | wc -l)" -ge 1 ]; }
_start() {
  _is_runing && container stop
  _is_runing -a && container rm -v
  docker run -d "$@" --name "$CONTAINER" \
  -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD=secret \
  "$IMAGE" --replSet rs
}
_mongo_status() {
  local FILTER=cat
  [ "$1" == "--prety" ] && FILTER=jq
  docker exec "$CONTAINER" \
  mongo --username 'root' --password 'secret' \
  --quiet --eval "JSON.stringify(rs.status())" | $FILTER
}
_dim() {
  ("$@" | perl -ne 's/\x1b\[([0-9;]+)m/\x1b[$1;2m/g; s/\n/\x1b[0m\n/; print " \x1b[32m| \x1b[0;2m$_"') 2>&1 \
    | perl -ne 'if (/^ \x1b\[32m| \x1b\[0;2m/){ print $_; } else { s/\x1b\[([0-9;]+)m/\x1b[$1;2m/g; print " \x1b[31m| \x1b[0;2m$_\x1b[0m"; }'
}

case "$1" in
build)
  shift
  exec docker build -t "$IMAGE" --build-arg "MONGO_TAG=$MONGO_TAG" "$@" .
  ;;
inspect)
  "$BASH_SOURCE" build && _start --rm || exit
  [ "$2" == "logs" ] && container logs -tf &
  trap '{ container stop; }' EXIT
  shift
  [ "$#" -eq 0 ] && set -- bash
  inspect
  ;;
exec)
  "$BASH_SOURCE" build && _start --rm || exit
  trap '{ container stop; }' EXIT
  shift
  [ "$#" -eq 0 ] && set -- bash
  docker exec -it "$CONTAINER" "$@"
  ;;
mongo)
  "$BASH_SOURCE" build && _start --rm || exit
  trap '{ container stop; }' EXIT
  wait-for --min=3 --msg="Wait for start..." --fail '[ "$(docker exec test-mongo mongo --host localhost --quiet --eval "1")" == 1 ]'
  shift
  docker exec -it "$CONTAINER" mongo --username 'root' --password 'secret' --quiet "$@"
  ;;
start)
  _start
  ;;
test)
  INSPECT="$2"
  "$BASH_SOURCE" build || exit
  trap '{ \
    echo -e "\x1b[33;2mClean up after...\x1b[0m"; \
    [ -z "$TEST_RESULT" -a "$INSPECT" == "inspect" ] && inspect; \
    _dim container stop; _dim container rm -v; _dim "$BASH_SOURCE" compose down -v; \
    echo -e "TEST_RESULT=${TEST_RESULT:-\x1b[31mFAIL\x1b[0m}"; \
  }' EXIT
  error() { echo -e "\x1b[31mError:\x1b[0m" "$@" >&2; }
  fail() { "$@"; exit 1; }

  _start 2>/dev/null || exit
  wait-for --min=3 --msg="Wait for 1st start..." --fail '[ "$(docker exec test-mongo mongo --host localhost --quiet --eval "print(1)")" == 1 ]'
  [ "$(_mongo_status | jq '.code')" == 94 ] || fail _mongo_status --prety
  LOGS="$(docker logs -t "$CONTAINER" | grep -F 'prestart-keyFile.sh: ')"; echo -e "\x1b[2m$LOGS\x1b[0m"
  [ "$(echo "$LOGS" | wc -l)" -eq 1 ] || fail error "--keyFile was not initialized with DB"
  container stop 2>/dev/null && container start 2>/dev/null || exit

  wait-for --min=3 --msg="Wait for 2nd start..." --fail '[ "$(docker exec test-mongo mongo --host localhost --quiet --eval "1")" == 1 ]'
  [ "$(_mongo_status | jq '.code')" == 94 ] || fail _mongo_status --prety
  LOGS="$(docker logs -t "$CONTAINER" | grep -F 'prestart-keyFile.sh: ')"; echo -e "\x1b[2m$LOGS\x1b[0m"
  [ "$(echo "$LOGS" | wc -l)" -eq 2 ] || fail error "--keyFile was not initialized when DB is already"

  "$BASH_SOURCE" compose up -d 2>/dev/null || exit

  wait-for --min=3 --msg="Wait for 1st cluster..." --fail '[ "$("$BASH_SOURCE" compose exec -T node1 mongo --quiet --eval "1")" -eq 1 ]'
  wait-for --msg="All nodes was initialized..." --fail --debug='"$BASH_SOURCE" compose logs 2>&1 | grep -F "prestart-keyFile.sh: "' \
    '[ "$("$BASH_SOURCE" compose logs 2>&1 | grep -F "prestart-keyFile.sh: " | wc -l)" -eq 3 ]'
  wait-for --msg="Check auto authorize mongo cli..." --fail \
    --debug='"$BASH_SOURCE" compose exec -T node1 mongo --quiet --eval "load('"'"'/root/.mongorc.js'"'"');print(JSON.stringify(rs.status()))" | jq' \
    '[ "$("$BASH_SOURCE" compose exec -T node1 mongo --quiet --eval "load('"'"'/root/.mongorc.js'"'"');print(rs.status().code)")" -eq 94 ]'
  RESULT="$("$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval \
  'JSON.stringify(rs.initiate({_id:"rs", members: [{_id:0,host:"node1:27017"},{_id:1,host:"node2:27017"},{_id:2,host:"node3:27017"}]}))')"
  [ "$(jq '.ok' <<<"$RESULT")" -eq 1 ] || fail jq <<<"$RESULT"
  wait-for --msg="Wait for cluster initialized..." --fail \
    --debug='"$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval "JSON.stringify(rs.status())" | jq' \
    '[ "$("$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval "JSON.stringify(rs.status())" | jq ".ok")" -eq 1 ]'
  "$BASH_SOURCE" compose stop 2>/dev/null || exit

  "$BASH_SOURCE" compose start 2>/dev/null || exit
  wait-for --min=3 --msg="Wait for 1st cluster 2nd start..." --fail \
    '[ "$("$BASH_SOURCE" compose exec -T node1 mongo --quiet --eval "1")" -eq 1 ]'
  wait-for --msg="All nodes was initialized 2nd time..." --fail \
    --debug='"$BASH_SOURCE" compose logs 2>&1 | grep -F "prestart-keyFile.sh: "' \
    '[ "$("$BASH_SOURCE" compose logs 2>&1 | grep -F "prestart-keyFile.sh: " | wc -l)" -eq 6 ]'
  wait-for --msg="Wait for cluster initialized..." --fail \
    --debug='"$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval "JSON.stringify(rs.status())" | jq' \
    '[ "$("$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval "JSON.stringify(rs.status())" | jq ".ok")" -eq 1 ]'
  "$BASH_SOURCE" compose down 2>/dev/null || exit

  CLUSTER_CONFIG='{_id:"rs", members: [{_id:0,host:"node1:27017"},{_id:1,host:"node2:27017"},{_id:2,host:"node3:27017"}]}' "$BASH_SOURCE" compose up -d 2>/dev/null || exit
  wait-for --min=3 --msg="Wait for 2nd cluster..." --fail '[ "$("$BASH_SOURCE" compose exec -T node1 mongo --quiet --eval "1")" -eq 1 ]'
  wait-for --msg="All nodes was initialized..." --fail \
    --debug='"$BASH_SOURCE" compose logs 2>&1 | grep -F "prestart-keyFile.sh: "' \
    '[ "$("$BASH_SOURCE" compose logs 2>&1 | grep -F "prestart-keyFile.sh: " | wc -l)" -eq 3 ]'
  wait-for --msg="Wait for cluster auto initialized..." --fail \
    --debug='"$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval "JSON.stringify(rs.status())" | jq' \
    '[ "$("$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval "JSON.stringify(rs.status())" | jq ".ok")" -eq 1 ]'

  TEST_RESULT='\x1b[32mOK\x1b[0m'
  ;;
push)
  shift
  "$BASH_SOURCE" test "$@" && docker push "$IMAGE"
  ;;
compose)
  shift
  cd "$(dirname "$BASH_SOURCE")"
  exec docker-compose "$@"
  ;;
*)
  echo "USAGE:"
  echo "  $(basename "$0") bulid"
  echo "  $(basename "$0") test"
  echo "  $(basename "$0") start  - a container in dettached mode"
  echo "  $(basename "$0") exec [<cmd> <arg>...]"
  echo "  $(basename "$0") push"
  ;;
esac
