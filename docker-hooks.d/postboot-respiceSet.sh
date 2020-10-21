if ! [  -f ~/.replicaSet.js ] && ! [ -z "${CLUSTER_CONFIG:-}" ]
then echo "($CLUSTER_CONFIG)" > ~/.replicaSet.js
fi
