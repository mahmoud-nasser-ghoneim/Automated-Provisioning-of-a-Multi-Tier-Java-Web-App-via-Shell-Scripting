#!/bin/bash
# web01 - Nginx reverse proxy. Runs as root, started by the VCD guest customization script.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root
exec >> /var/log/vprofile-provision.log 2>&1
echo "== $(date) start web01 =="

until timeout 3 bash -c '</dev/tcp/archive.ubuntu.com/80' 2>/dev/null; do sleep 5; done

apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 -y install nginx

cat > /etc/nginx/sites-available/vproapp <<'NGINX'
upstream vproapp {
    server app01:8080;
}

server {
    listen 80;
    location / {
        proxy_pass http://vproapp;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/vproapp /etc/nginx/sites-enabled/vproapp
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "== $(date) done web01 =="
