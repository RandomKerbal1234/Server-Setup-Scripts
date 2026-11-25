#!/usr/bin/env bash
# 40-firewall.sh - reproduce the FedoraWorkstation zone and Docker policy.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

svc_enable_now firewalld

log "installing firewalld zone and policy files"
install_file "$BUNDLE_DIR/etc/firewalld/zones/FedoraWorkstation.xml" \
  /etc/firewalld/zones/FedoraWorkstation.xml 644 root root
install_file "$BUNDLE_DIR/etc/firewalld/zones/docker.xml" \
  /etc/firewalld/zones/docker.xml 644 root root
install_file "$BUNDLE_DIR/etc/firewalld/policies/docker-forwarding.xml" \
  /etc/firewalld/policies/docker-forwarding.xml 644 root root

if [[ $DRY_RUN -eq 0 ]] && command -v restorecon >/dev/null 2>&1; then
  restorecon -R /etc/firewalld 2>/dev/null \
    || warn "restorecon failed for /etc/firewalld"
fi

log "reloading firewalld to load the zone and policy files"
run firewall-cmd --reload

log "setting default zone"
run firewall-cmd --set-default-zone=FedoraWorkstation

log "ensuring services and ports in the FedoraWorkstation zone"
for svc in dhcpv6-client http https samba-client ssh; do
  run firewall-cmd --permanent --zone=FedoraWorkstation --add-service="$svc"
done
for port in 1025-65535/tcp 1025-65535/udp; do
  run firewall-cmd --permanent --zone=FedoraWorkstation --add-port="$port"
done

log "reloading firewalld"
run firewall-cmd --reload

if [[ $DRY_RUN -eq 0 ]]; then
  firewall-cmd --zone=FedoraWorkstation --list-all | sed 's/^/    /'
fi

warn "the FedoraWorkstation zone opens all ports 1025-65535; narrow it if the target is Internet-facing"
ok "firewall step complete"
