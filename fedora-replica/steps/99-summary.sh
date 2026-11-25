#!/usr/bin/env bash
# 99-summary.sh - print the result and the post-install checklist.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

echo
log "summary"
printf '    domain:        %s\n' "$DOMAIN"
printf '    hostname:      %s\n' "$(hostname 2>/dev/null || echo unknown)"
printf '    backup dir:    %s\n' "$BACKUP_DIR"
printf '    secrets:       %s\n' "$([[ $WITH_SECRETS -eq 1 ]] && echo installed || echo not installed)"

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  warn "dry run: nothing above was actually changed"
  exit 0
fi

echo
log "listening ports"
ss -tlnp 2>/dev/null | awk 'NR==1 || $4 ~ /:(22|80|443|8080|9090|25565|11987|11988)$/' | sed 's/^/    /' || true

echo
log "service state"
for u in sshd firewalld nginx docker cockpit.socket chronyd tuned coolercontrold minecraft; do
  state=$(systemctl is-active "$u" 2>/dev/null || true)
  enabled=$(systemctl is-enabled "$u" 2>/dev/null || true)
  printf '    %-20s %-10s %s\n' "$u" "${state:-unknown}" "${enabled:-unknown}"
done

echo
log "web endpoints"
for url in "https://$DOMAIN/" "https://$DOMAIN/guac/" "https://$DOMAIN/files/" \
           "https://cockpit.$DOMAIN/" "https://127.0.0.1:9090/"; do
  code=$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo "---")
  printf '    %-40s %s\n' "$url" "$code"
done

echo
log "post-install checklist"
cat <<EOF
    1. Change the Guacamole admin password (default guacadmin / guacadmin)
       at https://$DOMAIN/guac/ .
    2. Set a password for andrey if you did not use --set-passwords:
         passwd andrey
    3. If nginx is using the self-signed placeholder, issue a real certificate:
         certbot --nginx -d $DOMAIN -d cockpit.$DOMAIN
       (or re-run step 50 with --certbot)
    4. Give the target a DHCP reservation or static address. The source used
       192.168.0.3/24 on eno1.
    5. Narrow the firewall if the host is Internet-facing. The
       FedoraWorkstation zone currently allows all ports 1025-65535.
    6. Review /var/www/files: nginx serves it with autoindex on.
    7. Start Minecraft if you did not use --start-minecraft:
         systemctl start minecraft
       The first start downloads the vanilla server and Fabric libraries.
    8. If Minecraft refuses to start because of duplicate mod IDs:
         ./scripts/dedupe-minecraft-mods.sh --apply
    9. Recreate Guacamole connections/users or restore a database dump.
       The replica creates only the schema, not the source data.
   10. Configure backups for /home/minecraft/server/world, the MySQL volume
       and /etc/letsencrypt.
EOF

echo
ok "done"
