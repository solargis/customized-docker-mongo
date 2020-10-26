if [ ! -z "${MONGO_INITDB_ROOT_USERNAME:-}" -a ! -z "${MONGO_INITDB_ROOT_PASSWORD:-}" ]; then
    _aux="db.getSiblingDB('admin').auth('$MONGO_INITDB_ROOT_USERNAME','$MONGO_INITDB_ROOT_PASSWORD');"
    if [ -r ~/.mongorc.js ] && [ "$(grep -F "$_aux" ~/.mongorc.js | wc -l)" -eq 1 ]; then
        echo "$BASH_SOURCE: mongo cli autologin is already configured in $(realpath ~/.mongorc.js)"
    else
        echo "$_aux" >> ~/.mongorc.js && chmod 0600 ~/.mongorc.js \
         && echo "$BASH_SOURCE: mongo cli autologin was configured in $(realpath ~/.mongorc.js)"
    fi
fi
