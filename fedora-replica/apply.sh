#!/usr/bin/env bash
# apply.sh - recreate the source Fedora host's configuration on a new server.
#
# Default mode is a dry run: nothing is changed. Use --apply to execute.
# Run as root on the target:
#
#   sudo ./apply.sh --apply --with-secrets
#
# See README.md for the full flag list and the post-install checklist.

set -euo pipefail

BUNDLE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export BUNDLE_DIR

umask 022

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

DRY_RUN=1
ASSUME_YES=0
WITH_SECRETS=0
DOMAIN="noadminabusearda.opik.net"
SOURCE_DOMAIN="noadminabusearda.opik.net"
TARGET_HOSTNAME="fedora"
NEXTCLOUD_UPSTREAM="http://192.168.0.4:8080"
MINECRAFT_HEAP="18G"
START_MINECRAFT=0
SET_PASSWORDS=0
CREATE_ALL_USERS=0
CERTBOT=0
CERTBOT_EMAIL=""
SKIP_PCP=0
SKIP_LIBVIRT=0
SKIP_COOLERCONTROL=0
SKIP_DOCKER=0
SKIP_MINECRAFT=0
ONLY=""
FROM=""
SKIPPED_IDS=""
BACKUP_DIR=""

STEPS=(
  00-preflight.sh
  10-packages.sh
  20-system.sh
  30-users.sh
  40-firewall.sh
  50-nginx.sh
  60-cockpit.sh
  70-coolercontrol.sh
  80-docker.sh
  90-minecraft.sh
  95-services.sh
  99-summary.sh
)

usage() {
  cat <<'EOF'
Usage: ./apply.sh [OPTIONS]

Modes:
  (default)              Dry run. Print every action without changing anything.
  --apply                Actually apply the configuration. Requires root.
  --yes                  Do not ask for confirmation in --apply mode.

Secrets and certificates:
  --with-secrets         Install secret material from secrets/ (TLS keys, real
                         server.properties, Guacamole compose file,
                         CoolerControl password). Wi-Fi profiles and mail
                         configs stay manual. Without this flag the replica
                         generates fresh passwords where possible and uses
                         placeholder certificates.
  --certbot              After nginx is up, issue a new Let's Encrypt
                         certificate with the nginx plugin.
  --email ADDRESS        ACME account email for --certbot.
  --set-passwords        Set the andrey password from
                         secrets/system/andrey-password.txt.

Target identity:
  --domain DOMAIN        Public DNS name (default: noadminabusearda.opik.net).
                         nginx and Cockpit configs are rendered with it.
  --hostname NAME        Static hostname (default: fedora).
  --nextcloud-upstream URL
                         Upstream for nextcloud.<domain>
                         (default: http://192.168.0.4:8080).
  --minecraft-heap SIZE  Java -Xmx value (default: 18G; use 4G on small hosts).
  --start-minecraft      Start the Minecraft service at the end. By default it
                         is enabled but not started, because the first start
                         downloads the vanilla server and Fabric libraries.
  --all-users            Also create the mom and ml accounts (UID 1002/1003).

Skips:
  --skip-coolercontrol   Do not install/configure CoolerControl.
  --skip-docker          Do not configure the Guacamole Docker stack.
  --skip-minecraft       Do not install the Minecraft server files/unit.
  --skip-pcp             Do not enable PCP (pmcd/pmie/pmlogger).
  --skip-libvirt         Do not install libvirt/virt-install.

Step selection:
  --only LIST            Comma/space separated step prefixes, e.g. "10,20,50".
  --from N               Run steps with a numeric prefix >= N, e.g. --from 40.
  --list-steps           Print the step list and exit.

Examples:
  sudo ./apply.sh                                  # dry run, everything
  sudo ./apply.sh --apply --yes --with-secrets     # full replica
  sudo ./apply.sh --apply --only 10,20,30          # packages/system/users
  sudo ./apply.sh --apply --from 50 --skip-docker  # web stack only
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)              DRY_RUN=0 ;;
    --dry-run)            DRY_RUN=1 ;;
    --yes|-y)             ASSUME_YES=1 ;;
    --with-secrets)       WITH_SECRETS=1 ;;
    --certbot)            CERTBOT=1 ;;
    --email)              CERTBOT_EMAIL=${2:?--email needs a value}; shift ;;
    --set-passwords)      SET_PASSWORDS=1 ;;
    --domain)             DOMAIN=${2:?--domain needs a value}; shift ;;
    --hostname)           TARGET_HOSTNAME=${2:?--hostname needs a value}; shift ;;
    --nextcloud-upstream) NEXTCLOUD_UPSTREAM=${2:?--nextcloud-upstream needs a value}; shift ;;
    --minecraft-heap)     MINECRAFT_HEAP=${2:?--minecraft-heap needs a value}; shift ;;
    --start-minecraft)    START_MINECRAFT=1 ;;
    --all-users)          CREATE_ALL_USERS=1 ;;
    --skip-coolercontrol) SKIPPED_IDS="$SKIPPED_IDS 70"; SKIP_COOLERCONTROL=1 ;;
    --skip-docker)        SKIPPED_IDS="$SKIPPED_IDS 80"; SKIP_DOCKER=1 ;;
    --skip-minecraft)     SKIPPED_IDS="$SKIPPED_IDS 90"; SKIP_MINECRAFT=1 ;;
    --skip-pcp)           SKIP_PCP=1 ;;
    --skip-libvirt)       SKIP_LIBVIRT=1 ;;
    --only)               ONLY=${2:?--only needs a value}; shift ;;
    --from)               FROM=${2:?--from needs a value}; shift ;;
    --list-steps)         printf '%s\n' "${STEPS[@]}"; exit 0 ;;
    -h|--help)            usage; exit 0 ;;
    *)                    echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

ONLY=${ONLY//,/ }
ONLY=${ONLY//  / }

export DRY_RUN ASSUME_YES WITH_SECRETS DOMAIN SOURCE_DOMAIN TARGET_HOSTNAME
export NEXTCLOUD_UPSTREAM MINECRAFT_HEAP START_MINECRAFT SET_PASSWORDS
export CREATE_ALL_USERS CERTBOT CERTBOT_EMAIL SKIP_PCP SKIP_LIBVIRT
export SKIP_COOLERCONTROL SKIP_DOCKER SKIP_MINECRAFT

# ---------------------------------------------------------------------------
# Step selection
# ---------------------------------------------------------------------------

step_id() { printf '%s' "${1%%-*}"; }

should_run() {
  local id=$1
  if [[ -n $ONLY ]]; then
    case " $ONLY " in
      *" $id "*) ;;
      *) return 1 ;;
    esac
  fi
  if [[ -n $FROM && "$id" < "$FROM" ]]; then
    return 1
  fi
  case " $SKIPPED_IDS " in
    *" $id "*) return 1 ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

if [[ $DRY_RUN -eq 0 ]]; then
  [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "run --apply as root (sudo)" >&2; exit 1; }
  BACKUP_DIR="/var/backups/fedora-replica-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
else
  BACKUP_DIR="/var/backups/fedora-replica-<timestamp>"
fi
export BACKUP_DIR

if [[ $WITH_SECRETS -eq 1 && ! -d $BUNDLE_DIR/secrets ]]; then
  echo "--with-secrets was given but $BUNDLE_DIR/secrets is missing" >&2
  exit 1
fi

if [[ ! -f $BUNDLE_DIR/lib.sh ]]; then
  echo "lib.sh not found next to apply.sh" >&2
  exit 1
fi

source "$BUNDLE_DIR/lib.sh"

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

echo
echo "fedora-replica"
echo "  bundle:    $BUNDLE_DIR"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "  mode:      DRY RUN (no changes)"
else
  echo "  mode:      APPLY"
  echo "  backups:   $BACKUP_DIR"
fi
echo "  domain:    $DOMAIN"
echo "  hostname:  $TARGET_HOSTNAME"
echo "  secrets:   $([[ $WITH_SECRETS -eq 1 ]] && echo yes || echo no)"
echo "  steps:     $(for s in "${STEPS[@]}"; do id=$(step_id "$s"); should_run "$id" && printf '%s ' "$id"; done)"
echo

if [[ $DRY_RUN -eq 0 ]]; then
  confirm "Apply this configuration to the current host?" || { echo "aborted"; exit 1; }
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

FAILED=()
for step in "${STEPS[@]}"; do
  id=$(step_id "$step")
  should_run "$id" || continue
  echo
  log "step $step"
  if ! bash "$BUNDLE_DIR/steps/$step"; then
    err "step $step failed"
    FAILED+=("$step")
    if [[ ${#FAILED[@]} -gt 0 && $DRY_RUN -eq 0 ]]; then
      err "stopping at the first failure; fix it and re-run with --from $id"
      exit 1
    fi
  fi
done

echo
if [[ ${#FAILED[@]} -gt 0 ]]; then
  err "completed with failures: ${FAILED[*]}"
  exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
  ok "dry run complete; re-run with --apply to make changes"
else
  ok "apply complete; run ./verify.sh to check the result"
fi
