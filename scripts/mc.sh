#!/bin/bash
# mc01 - Memcached. Runs as root, started by the VCD guest customization script.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root
exec >> /var/log/vprofile-provision.log 2>&1
echo "== $(date) start mc01 =="

until timeout 3 bash -c '</dev/tcp/archive.ubuntu.com/80' 2>/dev/null; do sleep 5; done

apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 -y install memcached

# listen on the network, not only on localhost
sed -i 's/^-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf
systemctl enable --now memcached
systemctl restart memcached

echo "== $(date) done mc01 =="
