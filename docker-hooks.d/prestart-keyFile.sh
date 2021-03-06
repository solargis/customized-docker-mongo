if _mongod_hack_have_arg --replSet "$@" \
  && _mongod_hack_have_arg --auth "$@" \
  && ! _mongod_hack_have_arg --keyFile "$@" \
  && mongod --help | grep -- ' --keyFile '
then
  KEY_FILE="$HOME/.keyFile"
  _mongod_hack_ensure_arg_val --keyFile "$KEY_FILE" "$@"
  set -- "${mongodHackedArgs[@]}"

  KEY="$(echo -n "$MONGO_INITDB_ROOT_PASSWORD" | openssl dgst -sha384 -binary | openssl base64 -A)"
  [ -w "$KEY_FILE" ] || ! [ -f "$KEY_FILE" ] || chmod u+w "$KEY_FILE"
  cat > "$KEY_FILE" <<< "$KEY"
  chmod 0400 "$KEY_FILE"
  echo "$BASH_SOURCE: added '--keyFile' '$KEY_FILE' (size $(wc -c "$KEY_FILE"))"
fi
