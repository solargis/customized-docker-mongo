if ! [ -z "${INIT_CLUSTER:-}" ] || ! [ -z "${INIT_USERS:-}" ]; then
    daemonize -e /dev/stderr -o /dev/stdout -l ~/init.lock -p ~/init.pid "$(which initializer)"
fi
