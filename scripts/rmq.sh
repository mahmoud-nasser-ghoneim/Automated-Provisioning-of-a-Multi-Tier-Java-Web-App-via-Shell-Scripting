#!/bin/bash
# rmq01 - RabbitMQ. Runs as root, started by the VCD guest customization script.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root
exec >> /var/log/vprofile-provision.log 2>&1
echo "== $(date) start rmq01 =="

until timeout 3 bash -c '</dev/tcp/archive.ubuntu.com/80' 2>/dev/null; do sleep 5; done

apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 -y install rabbitmq-server
systemctl enable --now rabbitmq-server

# application user (create only if missing)
if ! rabbitmqctl list_users | awk '{print $1}' | grep -qx test; then
  rabbitmqctl add_user test test
fi
rabbitmqctl set_user_tags test administrator
rabbitmqctl set_permissions -p / test ".*" ".*" ".*"

echo "== $(date) done rmq01 =="
