#!/usr/bin/env bash
# verify.sh - read-only checks for a target built by apply.sh.
#
# Usage:
#   sudo ./verify.sh
#   DOMAIN=example.com sudo -E ./verify.sh
#
# Exit status is 0 when there are no failures. Warnings do not fail the run.

set -uo pipefail

BUNDLE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOMAIN=${DOMAIN:-noadminabusearda.opik.net}

PASS=0
FAIL=0
WARN=0

if [[ -t 1 ]]; then
  G=$'\033[1;32m'; R=$'\033[1;31m'; Y=$'\033[1;33m'; B=$'\033[1;34m'; N=$'\033[0m'
else
  G=''; R=''; Y=''; B=''; N=''
fi

pass() { printf '%s[PASS]%s %s\n' "$G" "$N" "$*"; PASS=$((PASS + 1)); }
fail() { printf '%s[FAIL]%s %s\n' "$R" "$N" "$*"; FAIL=$((FAIL + 1)); }
warnc() { printf '%s[WARN]%s %s\n' "$Y" "$N" "$*"; WARN=$((WARN + 1)); }
section() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }

check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

check_shell() {
  local desc=$1 cmd=$2
  if bash -c "$cmd" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

check_file() {
  local desc=$1 path=$2
  if [[ -f $path ]]; then pass "$desc"; else fail "$desc ($path missing)"; fi
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || warnc "not running as root; some checks may be incomplete"

# ---------------------------------------------------------------------------
section "system"
# ---------------------------------------------------------------------------
check_shell "Fedora detected" "grep -q '^ID=fedora' /etc/os-release"
tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
if [[ $tz == America/New_York ]]; then
  pass "timezone is America/New_York"
else
  fail "timezone is '${tz:-unknown}', expected America/New_York"
fi
if [[ $(getenforce 2>/dev/null || echo Unknown) == Enforcing ]]; then
  pass "SELinux is enforcing"
else
  warnc "SELinux is not enforcing"
fi
if getsebool httpd_can_network_connect 2>/dev/null | grep -q 'on$'; then
  pass "SELinux boolean httpd_can_network_connect is on"
else
  fail "SELinux boolean httpd_can_network_connect is not on"
fi
if tuned-adm active 2>/dev/null | grep -q throughput-performance; then
  pass "tuned profile is throughput-performance"
else
  warnc "tuned profile is not throughput-performance"
fi

# ---------------------------------------------------------------------------
section "users"
# ---------------------------------------------------------------------------
check_shell "user andrey exists" "id andrey"
check_shell "user minecraft exists" "id minecraft"
check_shell "andrey is in wheel" "id -nG andrey | tr ' ' '\\n' | grep -qx wheel"
check_shell "andrey is in docker" "id -nG andrey | tr ' ' '\\n' | grep -qx docker"
check_shell "minecraft home exists" "test -d /home/minecraft"

# ---------------------------------------------------------------------------
section "packages"
# ---------------------------------------------------------------------------
for p in nginx firewalld cockpit certbot tuned docker-compose; do
  if rpm -q "$p" >/dev/null 2>&1; then
    pass "package $p"
  else
    fail "package $p is not installed"
  fi
done
if command -v docker >/dev/null 2>&1; then
  pass "docker command is available"
else
  fail "docker command is missing"
fi
if command -v java >/dev/null 2>&1; then
  java_major=$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -1)
  if [[ -n $java_major && $java_major -ge 21 ]]; then
    pass "java is available and new enough ($(java -version 2>&1 | head -1))"
  else
    fail "java is present but too old for Minecraft 1.21.11 ($(java -version 2>&1 | head -1))"
  fi
else
  fail "java is missing"
fi

# ---------------------------------------------------------------------------
section "services"
# ---------------------------------------------------------------------------
for u in sshd firewalld nginx docker cockpit.socket chronyd tuned; do
  if systemctl is-active --quiet "$u" 2>/dev/null; then
    pass "$u is active"
  else
    fail "$u is not active"
  fi
done
for u in sshd firewalld nginx docker cockpit.socket chronyd tuned certbot-renew.timer; do
  if systemctl is-enabled --quiet "$u" 2>/dev/null; then
    pass "$u is enabled"
  else
    warnc "$u is not enabled"
  fi
done

# ---------------------------------------------------------------------------
section "ports"
# ---------------------------------------------------------------------------
for port in 22 80 443 8080 9090; do
  if ss -tln 2>/dev/null | grep -q ":$port "; then
    pass "port $port is listening"
  else
    fail "port $port is not listening"
  fi
done
if systemctl is-active --quiet minecraft 2>/dev/null; then
  if ss -tln 2>/dev/null | grep -q ':25565'; then
    pass "Minecraft port 25565 is listening"
  else
    fail "Minecraft is active but 25565 is not listening"
  fi
else
  warnc "Minecraft is not running; 25565 is expected to be closed"
fi

# ---------------------------------------------------------------------------
section "nginx and TLS"
# ---------------------------------------------------------------------------
check_shell "nginx -t passes" "nginx -t"
for f in /etc/nginx/conf.d/cockpit.conf /etc/nginx/conf.d/homelab.conf \
         /etc/nginx/conf.d/nextcloud.conf /etc/cockpit/cockpit.conf \
         /etc/firewalld/zones/FedoraWorkstation.xml; do
  check_file "config $f" "$f"
done

if [[ -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]]; then
  pass "certificate for $DOMAIN exists"
  if openssl x509 -checkend 0 -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" >/dev/null 2>&1; then
    pass "certificate for $DOMAIN is not expired"
  else
    fail "certificate for $DOMAIN is expired"
  fi
  cert_file="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  issuer=$(openssl x509 -noout -issuer -in "$cert_file" 2>/dev/null | sed 's/^issuer=//')
  subject=$(openssl x509 -noout -subject -in "$cert_file" 2>/dev/null | sed 's/^subject=//')
  if [[ -n $issuer && $issuer == "$subject" ]]; then
    warnc "certificate for $DOMAIN is self-signed (placeholder)"
  elif [[ -n $issuer ]]; then
    pass "certificate for $DOMAIN is not self-signed"
  else
    fail "could not read the certificate for $DOMAIN"
  fi
  le_keys=$(find "/etc/letsencrypt/archive/$DOMAIN" -maxdepth 1 -name 'privkey*.pem' 2>/dev/null)
  if [[ -z $le_keys ]]; then
    warnc "no private key found under /etc/letsencrypt/archive/$DOMAIN"
  else
    le_bad=0
    while IFS= read -r k; do
      m=$(stat -c '%a' "$k" 2>/dev/null || echo unknown)
      [[ $m == 600 || $m == 400 ]] || le_bad=1
    done <<< "$le_keys"
    if [[ $le_bad -eq 1 ]]; then
      fail "Let's Encrypt private key permissions are too open"
    else
      pass "Let's Encrypt private key permissions are restrictive"
    fi
  fi
else
  fail "certificate for $DOMAIN is missing"
fi

if [[ -e /var/www/files/docker/guac-mysql/docker-compose.yml ]]; then
  warnc "the compose file with credentials is exposed under /var/www/files"
else
  pass "the compose file with credentials is not exposed under /var/www/files"
fi
check_file "/var/www/files/docker/guac-mysql/initdb.sql" "/var/www/files/docker/guac-mysql/initdb.sql"

# ---------------------------------------------------------------------------
section "firewall"
# ---------------------------------------------------------------------------
zone=$(firewall-cmd --get-default-zone 2>/dev/null || true)
if [[ $zone == FedoraWorkstation ]]; then
  pass "default firewalld zone is FedoraWorkstation"
else
  fail "default firewalld zone is '${zone:-unknown}'"
fi
for svc in http https ssh; do
  if firewall-cmd --zone=FedoraWorkstation --query-service="$svc" >/dev/null 2>&1; then
    pass "FedoraWorkstation allows $svc"
  else
    fail "FedoraWorkstation does not allow $svc"
  fi
done
if firewall-cmd --zone=FedoraWorkstation --query-port=25565/tcp >/dev/null 2>&1 || \
   firewall-cmd --zone=FedoraWorkstation --query-port=1025-65535/tcp >/dev/null 2>&1; then
  pass "Minecraft port is covered by the firewall"
else
  warnc "25565/tcp may not be reachable through firewalld"
fi

# ---------------------------------------------------------------------------
section "Docker and Guacamole"
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  running=$(docker ps --filter name=guac --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
  if [[ $running -eq 3 ]]; then
    pass "three Guacamole containers are running"
  else
    fail "expected 3 Guacamole containers, found ${running:-0}"
  fi
  dbpw=""
  if [[ -f /home/andrey/guac-mysql/.env ]]; then
    dbpw=$(sed -n 's/^MYSQL_ROOT_PASSWORD=//p' /home/andrey/guac-mysql/.env | head -1)
  fi
  if [[ -z $dbpw && -f /home/andrey/guac-mysql/docker-compose.yml ]]; then
    dbpw=$(awk '/MYSQL_ROOT_PASSWORD:/ {print $2; exit}' /home/andrey/guac-mysql/docker-compose.yml 2>/dev/null || true)
  fi
  dbpw=${dbpw%\"}; dbpw=${dbpw#\"}
  dbpw=${dbpw%\'}; dbpw=${dbpw#\'}
  if docker exec -e MYSQL_PWD="$dbpw" \
       guac-mysql mysql -uroot -N -B -e \
       "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='guacamole_db';" 2>/dev/null \
       | grep -qv '^0$'; then
    pass "guacamole_db has tables"
  else
    warnc "could not confirm the Guacamole schema (password may come from .env)"
  fi
  if curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:8080/guacamole/ 2>/dev/null; then
    pass "Guacamole responds on 8080"
  else
    fail "Guacamole does not respond on 8080"
  fi
  for f in /home/andrey/guac-mysql/docker-compose.yml /home/andrey/guac-mysql/.env; do
    if [[ -f $f ]]; then
      m=$(stat -c '%a' "$f" 2>/dev/null || echo unknown)
      if [[ $m == 600 || $m == 640 ]]; then
        pass "$f has restrictive permissions ($m)"
      else
        fail "$f has permissions $m (expected 600 or 640)"
      fi
    fi
  done
else
  fail "Docker daemon is not reachable"
fi

# ---------------------------------------------------------------------------
section "Minecraft"
# ---------------------------------------------------------------------------
check_file "minecraft.service" /etc/systemd/system/minecraft.service
check_shell "minecraft.service has ExecStart" "grep -q '^ExecStart=' /etc/systemd/system/minecraft.service"
if systemctl is-enabled --quiet minecraft.service 2>/dev/null; then
  pass "minecraft.service is enabled"
else
  warnc "minecraft.service is not enabled"
fi
if systemctl is-active --quiet minecraft.service 2>/dev/null; then
  pass "minecraft.service is active"
else
  warnc "minecraft.service is not active (start it with systemctl start minecraft)"
fi
check_file "server.jar" /home/minecraft/server/server.jar
check_shell "eula.txt is accepted" "grep -qi '^eula=true' /home/minecraft/server/eula.txt"
mods=$(find /home/minecraft/server/mods -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l | tr -d ' ')
if [[ ${mods:-0} -gt 0 ]]; then
  pass "Minecraft has $mods active mod jars"
else
  fail "no active Minecraft mod jars found"
fi
check_shell "serverconfig is present" "test -d /home/minecraft/server/world/serverconfig"
check_shell "server files are owned by minecraft" "test \"$(stat -c '%U' /home/minecraft/server/server.jar 2>/dev/null)\" = minecraft"
if [[ -f /home/minecraft/server/server.properties ]]; then
  if grep -q '^management-server-secret=CHANGE_ME' /home/minecraft/server/server.properties; then
    pass "server.properties uses the redacted management secret"
  else
    warnc "server.properties contains a real management secret; keep it mode 600"
    if [[ $(stat -c '%a' /home/minecraft/server/server.properties) != 600 ]]; then
      fail "server.properties contains a secret but is not mode 600"
    fi
  fi
fi

# ---------------------------------------------------------------------------
section "summary"
# ---------------------------------------------------------------------------
printf 'PASS: %d  FAIL: %d  WARN: %d\n' "$PASS" "$FAIL" "$WARN"
if [[ $FAIL -gt 0 ]]; then
  printf '%sverification failed%s\n' "$R" "$N"
  exit 1
fi
printf '%sverification passed%s\n' "$G" "$N"
