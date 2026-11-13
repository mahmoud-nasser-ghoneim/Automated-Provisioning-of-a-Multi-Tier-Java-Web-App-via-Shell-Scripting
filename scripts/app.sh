#!/bin/bash
# app01 - Tomcat + vprofile build. Runs as root, started by the VCD guest customization script.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root
exec >> /var/log/vprofile-provision.log 2>&1
echo "== $(date) start app01 =="

until timeout 3 bash -c '</dev/tcp/archive.ubuntu.com/80' 2>/dev/null; do sleep 5; done

apt-get -o DPkg::Lock::Timeout=600 update
apt-get -o DPkg::Lock::Timeout=600 -y install openjdk-17-jdk maven git wget netcat-openbsd

# Tomcat
TOMCAT_VER=9.0.75
if [ ! -x /usr/local/tomcat/bin/catalina.sh ]; then
  cd /tmp
  wget -q "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz"
  tar xzf "apache-tomcat-${TOMCAT_VER}.tar.gz"
  mkdir -p /usr/local/tomcat
  cp -r "apache-tomcat-${TOMCAT_VER}"/* /usr/local/tomcat/
fi
id tomcat >/dev/null 2>&1 || useradd --home-dir /usr/local/tomcat --shell /usr/sbin/nologin tomcat
chown -R tomcat:tomcat /usr/local/tomcat

# systemd service (--add-opens is required to run this old app on Java 17)
cat > /etc/systemd/system/tomcat.service <<'UNIT'
[Unit]
Description=Tomcat
After=network.target

[Service]
User=tomcat
WorkingDirectory=/usr/local/tomcat
Environment=JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
Environment=CATALINA_HOME=/usr/local/tomcat
Environment=CATALINA_BASE=/usr/local/tomcat
Environment="CATALINA_OPTS=--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED"
ExecStart=/usr/local/tomcat/bin/catalina.sh run
ExecStop=/usr/local/tomcat/bin/shutdown.sh
SyslogIdentifier=tomcat

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload

# wait until the backend services are reachable (they are provisioned in parallel)
for target in db01:3306 mc01:11211 rmq01:5672; do
  until nc -z "${target%%:*}" "${target##*:}"; do
    echo "waiting for ${target}"
    sleep 10
  done
done

# build the application
cd /root
[ -d vprofile-project ] || git clone -b main https://github.com/hkhcoder/vprofile-project.git
cd vprofile-project
mvn -B install

# deploy
systemctl stop tomcat || true
rm -rf /usr/local/tomcat/webapps/ROOT /usr/local/tomcat/webapps/ROOT.war
cp target/vprofile-v2.war /usr/local/tomcat/webapps/ROOT.war
chown -R tomcat:tomcat /usr/local/tomcat/webapps
systemctl enable tomcat
systemctl start tomcat

echo "== $(date) done app01 =="
