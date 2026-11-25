#!/usr/bin/env bash
# 30-users.sh - create the human/service accounts from the source.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

create_user() {
  local name=$1 uid=$2 gecos=$3 groups=${4:-}
  local uid_args=()

  if id "$name" >/dev/null 2>&1; then
    log "user $name already exists ($(id -u "$name"))"
  else
    if getent passwd "$uid" >/dev/null 2>&1; then
      warn "UID $uid is already taken by $(getent passwd "$uid" | cut -d: -f1); creating $name with the next free UID"
    else
      uid_args=(-u "$uid")
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '    [dry-run] useradd -m -s /bin/bash -c %q %s %s\n' \
        "$gecos" "${uid_args[*]:-}" "$name"
    else
      useradd -m -s /bin/bash -c "$gecos" ${uid_args[@]+"${uid_args[@]}"} "$name"
    fi
  fi

  local g
  for g in $groups; do
    if getent group "$g" >/dev/null 2>&1; then
      run usermod -aG "$g" "$name"
    else
      warn "group $g does not exist yet; add $name to it after installing the package that creates it"
    fi
  done
}

log "creating andrey (wheel, docker)"
create_user andrey 1000 "Andrey Krioukov" "wheel docker"

log "creating minecraft (service account)"
create_user minecraft 1001 "minecraft" ""

if [[ $CREATE_ALL_USERS -eq 1 ]]; then
  log "creating mom and ml (--all-users)"
  create_user mom 1002 "Mom" ""
  create_user ml 1003 "" ""
else
  log "not creating mom/ml (pass --all-users to include them)"
fi

log "home directory modes"
for h in /home/andrey /home/minecraft; do
  if [[ -d $h ]]; then
    run chmod 700 "$h"
  fi
done

log "passwords"
if [[ $SET_PASSWORDS -eq 1 ]]; then
  pwfile="$BUNDLE_DIR/secrets/system/andrey-password.txt"
  if [[ -r $pwfile ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '    [dry-run] set password for andrey from %s\n' "$pwfile"
    else
      printf 'andrey:%s\n' "$(cat "$pwfile")" | chpasswd
      ok "andrey password set from secrets/system/andrey-password.txt"
    fi
  else
    warn "password file not found: $pwfile"
  fi
else
  warn "andrey password not set; use --set-passwords or run 'passwd andrey'"
fi

# minecraft, mom and ml are intentionally left locked. The Minecraft service
# does not need a password; interactive logins for mom/ml should be set by the
# owner with passwd(1).

log "account summary"
for u in andrey minecraft mom ml; do
  if id "$u" >/dev/null 2>&1; then
    printf '    %-10s uid=%s groups=%s\n' "$u" "$(id -u "$u")" "$(id -Gn "$u")"
  fi
done

ok "user step complete"
