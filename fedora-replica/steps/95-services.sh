#!/usr/bin/env bash
# 95-services.sh - enable and start the server-relevant units.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

if [[ $DRY_RUN -eq 0 ]]; then
  systemctl daemon-reload
fi

log "restoring SELinux contexts on installed files"
if command -v restorecon >/dev/null 2>&1; then
  for p in /etc/nginx /etc/cockpit /etc/firewalld /etc/coolercontrol \
           /etc/letsencrypt /etc/samba /etc/tlog /etc/systemd/system \
           /etc/yum.repos.d /etc/sysconfig /etc/exports.d \
           /var/www/files /home/minecraft/server /home/andrey/guac-mysql; do
    if [[ -e $p ]]; then
      if [[ $DRY_RUN -eq 1 ]]; then
        printf '    [dry-run] restorecon -R %s\n' "$p"
      else
        restorecon -R "$p" 2>/dev/null || warn "restorecon failed for $p"
      fi
    fi
  done
else
  warn "restorecon not found; install policycoreutils and run restorecon manually"
fi

log "core services"
for u in sshd.service firewalld.service nginx.service \
         cockpit.socket chronyd.service rsyslog.service; do
  svc_enable_now "$u"
done
if [[ $SKIP_DOCKER -eq 0 ]]; then
  svc_enable_now docker.socket
  svc_enable_now docker.service
fi

log "tuning and hardware monitoring"
for u in tuned.service irqbalance.service lm_sensors.service \
         smartd.service thermald.service mcelog.service; do
  svc_enable_now "$u"
done

log "timers"
svc_enable_now fstrim.timer
svc_enable_now logrotate.timer
svc_enable_now certbot-renew.timer
svc_enable_now dnf-makecache.timer
if svc_exists dnf5-automatic.timer; then
  svc_enable_now dnf5-automatic.timer
elif svc_exists dnf-automatic.timer; then
  svc_enable_now dnf-automatic.timer
else
  warn "no dnf automatic timer found"
fi

if [[ $SKIP_PCP -eq 0 ]] && pkg_installed pcp; then
  log "PCP"
  for u in pmcd.service pmie.service pmlogger.service; do
    svc_enable_now "$u"
  done
else
  log "PCP not enabled"
fi

if [[ $SKIP_COOLERCONTROL -eq 0 ]] && \
   { pkg_installed coolercontrol || pkg_installed coolercontrold; }; then
  svc_enable_now coolercontrold.service
fi

if pkg_installed qemu-guest-agent; then
  svc_enable_now qemu-guest-agent.service
fi

# libvirtd is enabled but inactive on the source and there are no VMs. It is
# deliberately not enabled here.

if [[ $DRY_RUN -eq 0 ]]; then
  log "failed units"
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null || true)
  if [[ -n $failed ]]; then
    printf '%s\n' "$failed" | sed 's/^/    /'
    warn "some units failed; review them with systemctl status"
  else
    ok "no failed units"
  fi
fi

ok "service step complete"
