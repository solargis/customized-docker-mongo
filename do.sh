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
  while [ "${1:0:2}" == "--" ]; do case "${1/=*/}" in
  --max) MAX="${1/*=/}";;
  --step) STEP="${1/*=/}";;
  --msg) MSG="${1/*=/}";;
  --fail) EXIT="1";;
  esac; shift; done

  echo -en "$MSG \x1b[s"
  while ! eval "$@" 2>/dev/null; do
    echo -en "\x1b[u\x1b[0K\x1b[33m$(($MAX - $(date +%s) + $START))s \x1b[0;2m(timeout)\x1b[0m "
    if ! _is_runing; then echo -e "\x1b[u\x1b[0K\x1b[31mterminated\x1b[0m" && exit 1; fi
    if [ "$(( $(date +%s) - $START ))" -ge "$MAX" ]; then
      echo -e "\x1b[u\x1b[0K\x1b[31mtimeout \x1b[2m($(($(date +%s) - $START))s)\x1b[0m"
      [ -z "$EXIT" ] && return 1 || exit 1
    fi
    sleep "$STEP"
  done
  echo -e "\x1b[u\x1b[0K\x1b[32m$(($(date +%s) - $START))s\x1b[0m"
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
  docker exec -it "$CONTAINER" \
  mongo --username 'root' --password 'secret' \
  --quiet --eval "JSON.stringify(rs.status())" | $FILTER
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
  wait-for --msg="Wait for start..." --fail '[ "$(docker exec test-mongo mongo --quiet --eval "1")" -eq 1 ]'
  shift
  docker exec -it "$CONTAINER" mongo --username 'root' --password 'secret' --quiet "$@"
  ;;
test)
  INSPECT="$2"
  "$BASH_SOURCE" build && _start || exit
  trap '{ [ -z "$TEST_RESULT" -a "$INSPECT" == "inspect" ] && inspect; \
    container stop; container rm -v; "$BASH_SOURCE" compose down -v; \
    echo -e "TEST_RESULT=${TEST_RESULT:-\x1b[31mFAIL\x1b[0m}"; \
  }' EXIT
  error() { echo -e "\x1b[31mError:\x1b[0m" "$@" >&2; }
  fail() { "$@"; exit 1; }
  
  wait-for --msg="Wait for 1st start..." --fail '[ "$(docker exec test-mongo mongo --quiet --eval "1")" -eq 1 ]'
  [ "$(_mongo_status | jq '.code')" -eq 94 ] || fail _mongo_status --prety
  LOGS="$(docker logs -t "$CONTAINER" | grep -F 'auto-keyFile.sh: ')"; echo -e "\x1b[2m$LOGS\x1b[0m"
  [ "$(echo "$LOGS" | wc -l)" -eq 1 ] || fail error "--keyFile was not initialized with DB"
  container stop && container start || exit

  wait-for --msg="Wait for 2nd start..." --fail '[ "$(docker exec test-mongo mongo --quiet --eval "1")" -eq 1 ]'
  [ "$(_mongo_status | jq '.code')" -eq 94 ] || fail _mongo_status --prety
  LOGS="$(docker logs -t "$CONTAINER" | grep -F 'auto-keyFile.sh: ')"; echo -e "\x1b[2m$LOGS\x1b[0m"
  [ "$(echo "$LOGS" | wc -l)" -eq 2 ] || fail error "--keyFile was not initialized when DB is already"

  "$BASH_SOURCE" compose up -d || exit
  wait-for --msg="Wait for cluster..." --fail '[ "$("$BASH_SOURCE" compose exec -T node1 mongo --quiet --eval "1")" -eq 1 ]'
  "$BASH_SOURCE" compose logs | grep -F 'auto-keyFile.sh: '
  [ "$("$BASH_SOURCE" compose logs 2>&1 | grep -F 'auto-keyFile.sh: ' | wc -l)" -eq 3 ] || fail error "No all nodes was initialized"
  RESULT="$("$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval \
  'JSON.stringify(rs.initiate({_id:"rs", members: [{_id:0,host:"node1:27017"},{_id:1,host:"node2:27017"},{_id:2,host:"node3:27017"}]}))')"
  [ "$(jq '.ok' <<<"$RESULT")" -eq 1 ] || fail jq <<<"$RESULT"
  
  "$BASH_SOURCE" compose stop || exit
  "$BASH_SOURCE" compose start || exit
  wait-for --msg="Wait for cluster..." --fail '[ "$("$BASH_SOURCE" compose exec -T node1 mongo --quiet --eval "1")" -eq 1 ]'
  "$BASH_SOURCE" compose logs | grep -F 'auto-keyFile.sh: '
  [ "$("$BASH_SOURCE" compose logs 2>&1 | grep -F 'auto-keyFile.sh: ' | wc -l)" -eq 6 ] || fail error "No all nodes was initialized second time"
  sleep 1; RESULT="$("$BASH_SOURCE" compose exec -T node1 mongo -u root -p secret --quiet --eval 'JSON.stringify(rs.status())')"
  [ "$(jq '.ok' <<<"$RESULT")" -eq 1 ] || fail jq <<<"$RESULT"

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
  echo "  $(basename "$0") exec [<cmd> <arg>...]"
  echo "  $(basename "$0") push"
  ;;
esac
