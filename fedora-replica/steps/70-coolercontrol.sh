#!/usr/bin/env bash
# 70-coolercontrol.sh - CoolerControl daemon and UI configuration.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

COPR_REPO_NAME='_copr:copr.fedorainfracloud.org:codifryed:CoolerControl.repo'
COPR_REPO="$BUNDLE_DIR/etc/yum.repos.d/$COPR_REPO_NAME"

if ! pkg_installed coolercontrol && ! pkg_installed coolercontrold; then
  log "enabling the CoolerControl COPR repository"
  if command -v dnf >/dev/null 2>&1 && dnf copr --help >/dev/null 2>&1; then
    run dnf copr enable -y codifryed/CoolerControl || {
      warn "dnf copr enable failed; falling back to the bundled repo file"
      install_file "$COPR_REPO" "/etc/yum.repos.d/$COPR_REPO_NAME" 644 root root
    }
  else
    install_file "$COPR_REPO" "/etc/yum.repos.d/$COPR_REPO_NAME" 644 root root
  fi

  log "installing coolercontrol"
  pkg_install_best_effort coolercontrol
fi

if [[ $DRY_RUN -eq 0 ]] && ! pkg_installed coolercontrol && ! pkg_installed coolercontrold; then
  warn "CoolerControl is not available for this Fedora release; skipping its configuration"
  exit 0
fi

log "installing CoolerControl configuration"
ensure_dir /etc/coolercontrol 755
for f in config.toml alerts.json calibrations.json config-ui.json modes.json; do
  install_file "$BUNDLE_DIR/etc/coolercontrol/$f" "/etc/coolercontrol/$f" 644 root root
done

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p /var/lib/coolercontrol/plugins
  ln -sfn /var/lib/coolercontrol/plugins /etc/coolercontrol/plugins
fi

if [[ $WITH_SECRETS -eq 1 ]]; then
  log "installing CoolerControl password and TLS key"
  copy_secret "$BUNDLE_DIR/secrets/coolercontrol/passwd" \
    /etc/coolercontrol/.passwd 600 root root
  copy_secret "$BUNDLE_DIR/secrets/coolercontrol/coolercontrol.key" \
    /etc/coolercontrol/coolercontrol.key 600 root root
  copy_secret "$BUNDLE_DIR/secrets/coolercontrol/coolercontrol.crt" \
    /etc/coolercontrol/coolercontrol.crt 644 root root
else
  warn "CoolerControl login password not installed; the daemon will use its default local behavior"
fi

if [[ $DRY_RUN -eq 0 ]] && command -v restorecon >/dev/null 2>&1; then
  restorecon -R /etc/coolercontrol 2>/dev/null \
    || warn "restorecon failed for /etc/coolercontrol"
fi

svc_enable_now coolercontrold.service

if [[ $DRY_RUN -eq 0 ]]; then
  if svc_is_active coolercontrold.service; then
    ok "coolercontrold is running on 127.0.0.1:11987"
  else
    warn "coolercontrold failed to start; this is expected on hardware it does not support"
  fi
fi

ok "CoolerControl step complete"
