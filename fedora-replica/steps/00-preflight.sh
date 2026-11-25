#!/usr/bin/env bash
# 00-preflight.sh - verify that this looks like a safe target.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

require_root
need_cmd dnf
need_cmd systemctl
need_cmd openssl

log "target operating system"
if [[ ! -r /etc/os-release ]]; then
  die "/etc/os-release not found; is this Fedora?"
fi
# shellcheck disable=SC1091
. /etc/os-release
printf '    %s\n' "${PRETTY_NAME:-unknown}"
[[ ${ID:-} == fedora ]] || warn "this does not look like Fedora (ID=${ID:-unset})"
if [[ ${VERSION_ID:-0} != 43 ]]; then
  warn "source was Fedora 43; target is ${VERSION_ID:-unknown}. Package versions will differ."
fi
if [[ -n ${SUPPORT_END:-} ]]; then
  printf '    support end: %s\n' "$SUPPORT_END"
fi

log "safety checks"

# Refuse to run against the source host. The source machine-id is recorded in
# the inventory; applying the replica to the source would overwrite its config.
SOURCE_MACHINE_ID="e251dbe0cb974a98b456a31c9bf0510f"
if [[ -r /etc/machine-id ]]; then
  current_id=$(tr -d '[:space:]' < /etc/machine-id)
  if [[ $current_id == "$SOURCE_MACHINE_ID" ]]; then
    die "this is the source host (machine-id matches). Refusing to modify it."
  fi
fi

if [[ -d /home/minecraft/server && -n $(ls -A /home/minecraft/server 2>/dev/null || true) ]]; then
  warn "/home/minecraft/server already exists and is not empty; files will be backed up before replacement"
fi

if [[ -d /etc/letsencrypt && $WITH_SECRETS -eq 0 ]]; then
  warn "/etc/letsencrypt already exists; the bundle will not overwrite it without --with-secrets"
fi

if [[ $WITH_SECRETS -eq 1 ]]; then
  warn "secret material will be installed: TLS private keys, Guacamole DB password, real server.properties"
fi

if [[ $(getenforce 2>/dev/null || echo Unknown) != Enforcing ]]; then
  warn "SELinux is not enforcing; the source runs enforcing"
fi

log "resources"
avail_kb=$(df -Pk / | awk 'NR==2 {print $4}')
printf '    free on /: %s MB\n' "$((avail_kb / 1024))"
if [[ $avail_kb -lt 5000000 ]]; then
  warn "less than 5 GB free on /; Docker images and Minecraft downloads need several GB"
fi
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
printf '    RAM:       %s MB\n' "$mem_mb"
case "$MINECRAFT_HEAP" in
  *[gG]) heap_mb=$(( ${MINECRAFT_HEAP%[gG]} * 1024 )) ;;
  *[mM]) heap_mb=${MINECRAFT_HEAP%[mM]} ;;
  *)     heap_mb=0 ;;
esac
if [[ $mem_mb -gt 0 && $heap_mb -gt $((mem_mb - 1024)) ]]; then
  warn "Minecraft heap ${MINECRAFT_HEAP} is close to or larger than RAM (${mem_mb} MB); use --minecraft-heap 4G"
fi

log "network"
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 8 -o /dev/null https://fedoraproject.org 2>/dev/null; then
    ok "outbound HTTPS works"
  else
    warn "could not reach fedoraproject.org; dnf, Docker pulls and Minecraft first start will fail"
  fi
else
  warn "curl is not installed yet"
fi

log "bundle integrity"
for f in lib.sh etc/nginx/conf.d/homelab.conf etc/nginx/conf.d/cockpit.conf \
         etc/firewalld/zones/FedoraWorkstation.xml \
         docker/guac-mysql/initdb.sql minecraft/server.jar; do
  [[ -e $BUNDLE_DIR/$f ]] || die "bundle is missing $f"
done
ok "core bundle files are present"

if command -v sha256sum >/dev/null 2>&1 && [[ -f $BUNDLE_DIR/MANIFEST.sha256 ]]; then
  if (cd "$BUNDLE_DIR" && sha256sum -c --quiet MANIFEST.sha256 >/dev/null 2>&1); then
    ok "MANIFEST.sha256 matches the non-secret bundle"
  else
    warn "MANIFEST.sha256 does not match; the bundle was modified after it was generated"
    warn "regenerate it with ./scripts/make-manifest.sh if the changes are intentional"
  fi
else
  warn "sha256sum or MANIFEST.sha256 is unavailable; skipping checksum verification"
fi

if [[ $WITH_SECRETS -eq 1 && -f $BUNDLE_DIR/secrets/SHA256SUMS ]]; then
  if command -v sha256sum >/dev/null 2>&1; then
    if (cd "$BUNDLE_DIR" && sha256sum -c --quiet secrets/SHA256SUMS >/dev/null 2>&1); then
      ok "secrets/SHA256SUMS matches the secret files"
    else
      warn "secrets/SHA256SUMS does not match; secret files were modified after generation"
    fi
  else
    warn "sha256sum is unavailable; skipping secret checksum verification"
  fi
fi

if [[ $WITH_SECRETS -eq 1 ]]; then
  for f in secrets/system/andrey-password.txt \
           secrets/docker/guac-mysql/docker-compose.yml \
           secrets/minecraft/server.properties; do
    [[ -e $BUNDLE_DIR/$f ]] || warn "expected secret missing: $f"
  done
  if [[ -d $BUNDLE_DIR/secrets/letsencrypt ]]; then
    if [[ $DOMAIN == "$SOURCE_DOMAIN" ]]; then
      ok "Let's Encrypt material is available for $DOMAIN"
    else
      warn "the bundled certificate is for $SOURCE_DOMAIN, not $DOMAIN; it will be skipped"
    fi
  fi
fi

log "preflight complete"
