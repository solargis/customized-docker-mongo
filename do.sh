#!/bin/bash
cd "$(dirname "$BASH_SOURCE")"
MONGO_TAG="${MONGO_TAG:-4.2}"
IMAGE="solargis/mongo:${TAG:-$MONGO_TAG}"
CONTAINER="test-mongo"

case "$1" in
build)
  shift
  exec docker build -t "$IMAGE" --build-arg "MONGO_TAG=$MONGO_TAG" "$@" .
  ;;
exec)
  "$BASH_SOURCE" build && docker run --rm -d --name "$CONTAINER" "$IMAGE" --replSet rs || exit
  trap '{ docker stop "$CONTAINER"; }' EXIT
  shift
  [ "$#" -eq 0 ] && set -- bash
  docker exec -it "$CONTAINER" "$@"
  ;;
test)
  shift
  "$BASH_SOURCE" build "$@" && docker run --rm -d --name "$CONTAINER" "$IMAGE" --replSet rs || exit
  trap '{ docker stop "$CONTAINER"; echo "TEST_RESULT=${TEST_RESULT:-FAIL}"; }' EXIT
  sleep 5
  [ "$(docker exec -it "$CONTAINER" mongo --quiet --eval 'rs.status()' | jq '.code')" -eq 94 ] && TEST_RESULT=OK
  ;;
push)
  shift
  "$BASH_SOURCE" test "$@" && docker push "$IMAGE"
  ;;
*)
  echo "USAGE:"
  echo "  $(basename "$0") bulid"
  echo "  $(basename "$0") test"
  echo "  $(basename "$0") exec [<cmd> <arg>...]"
  echo "  $(basename "$0") push"
  ;;
esac
