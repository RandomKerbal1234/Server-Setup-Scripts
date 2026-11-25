#!/usr/bin/env bash
# lib.sh - shared helpers for the fedora-replica apply steps.
#
# This file is sourced by apply.sh and by every steps/*.sh script. It expects
# the following environment variables (all exported by apply.sh):
#
#   BUNDLE_DIR          absolute path to this bundle
#   DRY_RUN             1 = print actions, 0 = execute
#   WITH_SECRETS        1 = install secret material from secrets/
#   DOMAIN              public domain used in nginx/cockpit configs
#   SOURCE_DOMAIN       domain as it appears in the bundled files
#   NEXTCLOUD_UPSTREAM  upstream for nextcloud.<domain>
#   BACKUP_DIR          where replaced files are backed up
#   TARGET_HOSTNAME     hostname to set
#   MINECRAFT_HEAP      Java -Xmx value
#   START_MINECRAFT     1 = start the Minecraft service
#   SET_PASSWORDS       1 = set the andrey password from secrets/
#   CREATE_ALL_USERS    1 = also create mom and ml
#   CERTBOT             1 = issue a new Let's Encrypt certificate
#   CERTBOT_EMAIL       optional ACME account email
#
# The helpers are intentionally small and idempotent. Every destructive action
# goes through backup_path() first.

set -euo pipefail

: "${BUNDLE_DIR:?BUNDLE_DIR is not set}"
: "${DRY_RUN:=1}"
: "${WITH_SECRETS:=0}"
: "${DOMAIN:=noadminabusearda.opik.net}"
: "${SOURCE_DOMAIN:=noadminabusearda.opik.net}"
: "${NEXTCLOUD_UPSTREAM:=http://192.168.0.4:8080}"
: "${BACKUP_DIR:=/var/backups/fedora-replica}"
: "${TARGET_HOSTNAME:=fedora}"
: "${MINECRAFT_HEAP:=18G}"
: "${START_MINECRAFT:=0}"
: "${SET_PASSWORDS:=0}"
: "${CREATE_ALL_USERS:=0}"
: "${CERTBOT:=0}"
: "${CERTBOT_EMAIL:=}"
: "${SKIP_PCP:=0}"
: "${SKIP_LIBVIRT:=0}"
: "${SKIP_COOLERCONTROL:=0}"
: "${SKIP_DOCKER:=0}"
: "${SKIP_MINECRAFT:=0}"

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'
else
  C_RESET=''; C_BLUE=''; C_YELLOW=''; C_RED=''; C_GREEN=''
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[error]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Execution wrappers
# ---------------------------------------------------------------------------

# run CMD... - execute, or print in dry-run mode.
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# run_shell 'COMMAND STRING' - execute through bash, or print in dry-run mode.
run_shell() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] %s\n' "$*"
  else
    bash -c "$*"
  fi
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "run this as root (sudo ./apply.sh --apply ...)"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

confirm() {
  local prompt=${1:-"Continue?"} reply
  [[ ${ASSUME_YES:-0} -eq 1 ]] && return 0
  if [[ ! -t 0 ]]; then
    die "not a terminal; pass --yes to run non-interactively"
  fi
  read -r -p "$prompt [y/N] " reply
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

# ---------------------------------------------------------------------------
# Files and backups
# ---------------------------------------------------------------------------

ensure_dir() {
  local dir=$1 mode=${2:-755}
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] mkdir -p -m %s %s\n' "$mode" "$dir"
  else
    mkdir -p "$dir"
    chmod "$mode" "$dir"
  fi
}

backup_path() {
  local path=$1 rel target
  [[ -e $path || -L $path ]] || return 0
  rel=${path#/}
  target="$BACKUP_DIR/$rel"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] backup %s -> %s\n' "$path" "$target"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  cp -a "$path" "$target"
}

# install_file SRC DST [MODE] [OWNER] [GROUP]
install_file() {
  local src=$1 dst=$2 mode=${3:-644} owner=${4:-root} group=${5:-root}
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] install %s -> %s (%s %s:%s)\n' \
      "$src" "$dst" "$mode" "$owner" "$group"
    return 0
  fi
  [[ -f $src ]] || die "missing source file: $src"
  mkdir -p "$(dirname "$dst")"
  if [[ -f $dst ]] && cmp -s "$src" "$dst"; then
    chmod "$mode" "$dst"
    chown "$owner:$group" "$dst"
    return 0
  fi
  backup_path "$dst"
  cp -f "$src" "$dst"
  chmod "$mode" "$dst"
  chown "$owner:$group" "$dst"
}

# install_template SRC DST [MODE] [OWNER] [GROUP]
# Renders the source domain and Nextcloud upstream, then installs the result.
install_template() {
  local src=$1 dst=$2 mode=${3:-644} owner=${4:-root} group=${5:-root}
  local tmp rc=0
  [[ -f $src ]] || die "missing template: $src"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] render %s -> %s (%s %s:%s)\n' \
      "$src" "$dst" "$mode" "$owner" "$group"
    return 0
  fi
  tmp=$(mktemp "${TMPDIR:-/tmp}/fedreplica.XXXXXX")
  sed -e "s|${SOURCE_DOMAIN}|${DOMAIN}|g" \
      -e "s|http://192.168.0.4:8080|${NEXTCLOUD_UPSTREAM}|g" \
      "$src" > "$tmp" || rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "$tmp"
    die "failed to render $src"
  fi
  install_file "$tmp" "$dst" "$mode" "$owner" "$group" || rc=$?
  rm -f "$tmp"
  return $rc
}

# copy_tree SRC DST - copy the contents of SRC into DST.
copy_tree() {
  local src=$1 dst=$2
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] copy tree %s/. -> %s/\n' "$src" "$dst"
    return 0
  fi
  [[ -d $src ]] || die "missing source directory: $src"
  mkdir -p "$dst"
  cp -a "$src/." "$dst/"
}

# copy_secret SRC DST [MODE] [OWNER] [GROUP]
copy_secret() {
  local src=$1 dst=$2 mode=${3:-600} owner=${4:-root} group=${5:-root}
  if [[ ! -e $src ]]; then
    warn "secret not found, skipping: $src"
    return 0
  fi
  install_file "$src" "$dst" "$mode" "$owner" "$group"
}

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------

pkg_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

# pkg_install_best_effort PKG... - install what is missing, warn on failures.
pkg_install_best_effort() {
  local pkgs=("$@") p missing=()
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  for p in "${pkgs[@]}"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    log "packages already present: ${pkgs[*]}"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    log "would install: ${missing[*]}"
    return 0
  fi
  if dnf install -y "${missing[@]}"; then
    return 0
  fi
  warn "bulk install failed; retrying one package at a time"
  for p in "${missing[@]}"; do
    dnf install -y "$p" || warn "could not install $p"
  done
}

# pkg_install_required PKG... - fail if any package cannot be installed.
pkg_install_required() {
  local pkgs=("$@") p missing=()
  for p in "${pkgs[@]}"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    log "packages already present: ${pkgs[*]}"
    return 0
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    log "would install: ${missing[*]}"
    return 0
  fi
  dnf install -y "${missing[@]}" || die "failed to install: ${missing[*]}"
}

# ---------------------------------------------------------------------------
# systemd
# ---------------------------------------------------------------------------

svc_exists() {
  systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .
}

svc_enable() {
  local u=$1
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] systemctl enable %s\n' "$u"
    return 0
  fi
  if svc_exists "$u"; then
    systemctl enable "$u" >/dev/null 2>&1 || warn "could not enable $u"
  else
    warn "unit not found: $u"
  fi
}

svc_enable_now() {
  local u=$1
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] systemctl enable --now %s\n' "$u"
    return 0
  fi
  if svc_exists "$u"; then
    systemctl enable --now "$u" >/dev/null 2>&1 || warn "could not enable/start $u"
  else
    warn "unit not found: $u"
  fi
}

svc_start() {
  local u=$1
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] systemctl start %s\n' "$u"
    return 0
  fi
  if svc_exists "$u"; then
    systemctl start "$u" >/dev/null 2>&1 || warn "could not start $u"
  else
    warn "unit not found: $u"
  fi
}

svc_is_active() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

rand_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
  fi
}

# require_secrets - abort if a step needs secrets but --with-secrets was not used.
require_secrets() {
  [[ $WITH_SECRETS -eq 1 ]] || die "this step needs --with-secrets"
}
