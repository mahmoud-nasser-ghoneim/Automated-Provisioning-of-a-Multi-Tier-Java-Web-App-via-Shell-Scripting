#!/bin/bash
# db01 - MariaDB. Runs as root, started by the VCD guest customization script.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root
exec >> /var/log/vprofile-provision.log 2>&1
echo "== $(date) start db01 =="

# wait until DNS + internet work
until timeout 3 bash -c '</dev/tcp/archive.ubuntu.com/80' 2>/dev/null; do sleep 5; done

apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 -y install git mariadb-server

# listen on the network, not only on localhost
sed -i -E 's/^#?\s*bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl enable --now mariadb
systemctl restart mariadb

# database and application user
mysql <<'SQL'
CREATE DATABASE IF NOT EXISTS accounts;
GRANT ALL PRIVILEGES ON accounts.* TO 'admin'@'%' IDENTIFIED BY 'admin123';
FLUSH PRIVILEGES;
SQL

# load the initial data only once
cd /root
[ -d vprofile-project ] || git clone -b main https://github.com/hkhcoder/vprofile-project.git
if [ -z "$(mysql -N accounts -e 'show tables;')" ]; then
  mysql accounts < vprofile-project/src/main/resources/db_backup.sql
fi

echo "== $(date) done db01 =="
