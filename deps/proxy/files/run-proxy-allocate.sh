#!/bin/sh

#
# License: https://github.com/cadeworks/cade/blob/master/LICENSE
#

# set -e :: can not set to an error, because it is expected some call are failed

# TODO /w/w blocks until cade-bootstrap container receives assigned IP address
# TODO unfortunately, it may never happen, if weave node can not join successfully
# TODO it is better to check it's status before launching this script and report the status to a user

# weaveid, token, volume, placement, public_ip, seeds, seed_id
data="$1,$2,$3,$4,$5,${6//,/:},$7"

if [ -z "$6" ];
then
    echo "[cade proxy-allocate] internal error detected, proxy-allocate should be invoked with at least 6 arguments, exiting..." >&2
    echo "[cade proxy-allocate] received ${data}" >&2
    exit 1
fi

# TODO document what to do if it hangs on the following lines:
# it is necessary to open UDP port 6783 for inter-node communication over weave net
echo "[cade proxy-allocate] connecting to cade-etcd service"
curl --fail -s http://cade-etcd:2379/v2/keys > /dev/null
while [ $? -ne 0 ]; do
    echo "[cade proxy-allocate] waiting for cade-etcd service"
    sleep 1
    curl --fail -sS http://cade-etcd:2379/v2/keys > /dev/null
done

# bootstrap storage
curl --fail -s http://cade-etcd:2379/v2/keys/nodes > /dev/null
if [ $? -ne 0 ]; then
    echo "[cade proxy-allocate] bootstraping cade-etcd storage"
    curl --fail -sS -XPUT http://cade-etcd:2379/v2/keys/nodes -d dir=true > /dev/null || true
    curl --fail -sS -XPUT http://cade-etcd:2379/v2/keys/services -d dir=true > /dev/null  || true
    curl --fail -sS -XPUT http://cade-etcd:2379/v2/keys/ips -d dir=true > /dev/null  || true
    curl --fail -sS -XPUT http://cade-etcd:2379/v2/keys/credentials -d dir=true > /dev/null  || true
    curl --fail -sS -XPUT http://cade-etcd:2379/v2/keys/files -d dir=true > /dev/null  || true
fi

current_id=1
echo "[cade proxy-allocate] scanning for the next available node id: ${current_id}"
curl --fail -s -X PUT http://cade-etcd:2379/v2/keys/nodes/${current_id}?prevExist=false -d value="${data}" > /dev/null
while [ $? -ne 0 ]; do
    current_id=$((current_id+1))
    echo "[cade proxy-allocate] scanning for the next available node id: ${current_id}"
    curl --fail -s -X PUT http://cade-etcd:2379/v2/keys/nodes/${current_id}?prevExist=false -d value="${data}" > /dev/null
done

echo "[cade proxy-allocate] allocated node id: ${current_id}"
echo ${current_id} > /data/nodeid.txt
