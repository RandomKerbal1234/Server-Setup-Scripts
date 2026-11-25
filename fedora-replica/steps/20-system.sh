#!/usr/bin/env bash
# 20-system.sh - identity, time, locale, tuned, SELinux, timers.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

log "hostname"
run hostnamectl set-hostname "$TARGET_HOSTNAME"

log "timezone and clock"
run timedatectl set-timezone America/New_York
if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking 2>/dev/null | sed 's/^/    /' || true
fi

log "locale"
run localectl set-locale LANG=en_US.UTF-8
if command -v locale >/dev/null 2>&1; then
  locale 2>/dev/null | sed -n '1,3p' | sed 's/^/    /' || true
fi

log "tuned profile"
if command -v tuned-adm >/dev/null 2>&1; then
  run tuned-adm profile throughput-performance
else
  warn "tuned-adm not found; install tuned and re-run this step"
fi

log "SELinux booleans"
if command -v setsebool >/dev/null 2>&1; then
  for b in httpd_can_network_connect selinuxuser_execmod \
           virt_sandbox_use_all_caps virt_use_nfs; do
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '    [dry-run] setsebool -P %s on\n' "$b"
    elif setsebool -P "$b" on 2>/dev/null; then
      printf '    %s = on\n' "$b"
    else
      warn "could not set SELinux boolean $b (not present on this policy?)"
    fi
  done
else
  warn "setsebool not found; install policycoreutils"
fi

log "session recording, sensors and Samba configuration"
install_file "$BUNDLE_DIR/etc/tlog/tlog-rec-session.conf" \
  /etc/tlog/tlog-rec-session.conf 644 root root
install_file "$BUNDLE_DIR/etc/sysconfig/lm_sensors" \
  /etc/sysconfig/lm_sensors 644 root root
install_file "$BUNDLE_DIR/etc/samba/smb.conf" \
  /etc/samba/smb.conf 644 root root
install_file "$BUNDLE_DIR/etc/exports.d/cockpit-file-sharing.exports" \
  /etc/exports.d/cockpit-file-sharing.exports 644 root root
warn "lm_sensors is configured for the source's coretemp driver; adjust it if the target CPU differs"

log "dnf automatic timer schedule (Monday 00:00, matching the source)"
timer_dropin_installed=0
if [[ $DRY_RUN -eq 1 ]] || svc_exists dnf5-automatic.timer; then
  install_file "$BUNDLE_DIR/etc/systemd/system/dnf5-automatic.timer.d/time.conf" \
    /etc/systemd/system/dnf5-automatic.timer.d/time.conf 644 root root
  timer_dropin_installed=1
fi
if svc_exists dnf-automatic.timer; then
  install_file "$BUNDLE_DIR/etc/systemd/system/dnf5-automatic.timer.d/time.conf" \
    /etc/systemd/system/dnf-automatic.timer.d/time.conf 644 root root
  timer_dropin_installed=1
fi
[[ $timer_dropin_installed -eq 1 ]] || warn "no dnf automatic timer unit found"

log "default systemd target"
run systemctl set-default multi-user.target

log "trim timer"
svc_enable fstrim.timer

if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload
fi

ok "system step complete"
