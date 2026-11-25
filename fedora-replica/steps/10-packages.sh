#!/usr/bin/env bash
# 10-packages.sh - install the server-relevant package set.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

log "refreshing dnf metadata"
run dnf makecache -y >/dev/null 2>&1 || warn "dnf makecache failed; continuing"

log "core system and web packages"
pkg_install_best_effort \
  nginx certbot python3-certbot-nginx \
  firewalld chrony rsyslog \
  openssh-server sudo \
  policycoreutils policycoreutils-python-utils setools-console \
  glibc-langpack-en zram-generator btrfs-progs \
  curl wget2-wget git jq unzip tar rsync \
  tmux screen htop vim-enhanced \
  dnf5-plugins dnf5-plugin-automatic

log "hardware monitoring and tuning"
pkg_install_best_effort \
  tuned irqbalance lm_sensors smartmontools thermald mcelog

log "Cockpit"
pkg_install_best_effort \
  cockpit cockpit-files cockpit-networkmanager cockpit-packagekit \
  cockpit-storaged cockpit-system cockpit-machines \
  cockpit-session-recording tlog

log "network file system clients"
pkg_install_best_effort nfs-utils samba-client

if [[ $SKIP_DOCKER -eq 1 ]]; then
  log "skipping Docker packages (--skip-docker)"
else
  log "containers"
  if ! pkg_installed moby-engine && ! pkg_installed docker; then
    if [[ $DRY_RUN -eq 1 ]]; then
      log "would install: moby-engine docker-cli docker-compose docker-buildx containerd"
    elif ! dnf install -y moby-engine docker-cli docker-compose docker-buildx containerd; then
      warn "moby-engine transaction failed; trying the docker package set"
      dnf install -y docker docker-compose docker-buildx containerd \
        || warn "could not install a Docker engine; step 80 will be skipped"
    fi
  else
    log "a Docker engine is already installed"
  fi
  pkg_install_best_effort docker-compose-switch
fi

log "Java for Minecraft"
java_major=""
if command -v java >/dev/null 2>&1; then
  java_major=$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -1)
fi
if [[ -n $java_major && $java_major -ge 21 ]]; then
  log "java already present: $(java -version 2>&1 | head -1)"
else
  if command -v java >/dev/null 2>&1; then
    if [[ -n $java_major ]]; then
      warn "java $java_major is too old for Minecraft 1.21.11; installing Java 25"
    else
      warn "java is present but its version could not be determined; installing Java 25"
    fi
  fi
  installed_java=0
  for jpkg in java-25-openjdk-headless java-21-openjdk-headless java-latest-openjdk-headless; do
    if [[ $DRY_RUN -eq 1 ]]; then
      log "would try: $jpkg"
      installed_java=1
      break
    fi
    if dnf install -y "$jpkg"; then
      installed_java=1
      break
    fi
    warn "could not install $jpkg; trying the next Java package"
  done
  [[ $installed_java -eq 1 ]] || warn "no Java runtime installed; Minecraft will not start"
fi

if [[ $SKIP_PCP -eq 0 ]]; then
  log "Performance Co-Pilot"
  pkg_install_best_effort pcp python3-pcp
else
  log "skipping PCP (--skip-pcp)"
fi

if [[ $SKIP_LIBVIRT -eq 0 ]]; then
  log "virtualization (installed but not enabled)"
  pkg_install_best_effort libvirt-daemon-kvm virt-install
else
  log "skipping libvirt (--skip-libvirt)"
fi

log "optional guest agent (only useful inside a VM)"
pkg_install_best_effort qemu-guest-agent

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

log "installed versions"
for p in nginx firewalld cockpit docker-compose moby-engine docker tuned java-25-openjdk-headless; do
  if pkg_installed "$p"; then
    rpm -q "$p" | sed 's/^/    /'
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  warn "docker command is not available; the Guacamole stack cannot be deployed"
fi

ok "package step complete"
