#!/usr/bin/env bash
# 60-cockpit.sh - Cockpit web console.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

log "installing cockpit.conf"
install_template "$BUNDLE_DIR/etc/cockpit/cockpit.conf" \
  /etc/cockpit/cockpit.conf 644 root root

if [[ $DRY_RUN -eq 0 ]] && command -v restorecon >/dev/null 2>&1; then
  restorecon -R /etc/cockpit 2>/dev/null \
    || warn "restorecon failed for /etc/cockpit"
fi

log "enabling cockpit.socket"
svc_enable_now cockpit.socket

if [[ $DRY_RUN -eq 0 ]]; then
  if svc_is_active cockpit.socket; then
    ok "cockpit.socket is listening on 9090"
  else
    warn "cockpit.socket is not active; check 'systemctl status cockpit.socket'"
  fi
fi

ok "cockpit step complete"
