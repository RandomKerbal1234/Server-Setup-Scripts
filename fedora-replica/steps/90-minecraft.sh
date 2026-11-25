#!/usr/bin/env bash
# 90-minecraft.sh - Fabric server files, mods, configs and systemd unit.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

SERVER_DIR=/home/minecraft/server

if ! id minecraft >/dev/null 2>&1; then
  die "user minecraft does not exist; run step 30 first"
fi

case "$MINECRAFT_HEAP" in
  [0-9]*[Gg]|[0-9]*[Mm]) ;;
  *) die "invalid --minecraft-heap '$MINECRAFT_HEAP' (use e.g. 18G or 4G)" ;;
esac

log "creating $SERVER_DIR"
if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] install -d -o minecraft -g minecraft -m 755 %s\n' "$SERVER_DIR"
else
  install -d -o minecraft -g minecraft -m 755 "$SERVER_DIR"
  chown minecraft:minecraft "$SERVER_DIR"
fi

log "copying server jar, mods, configs and map configs"
if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] rsync -a --backup --exclude systemd --exclude serverconfig %s/ %s/\n' \
    "$BUNDLE_DIR/minecraft" "$SERVER_DIR"
else
  if command -v rsync >/dev/null 2>&1; then
    mkdir -p "$BACKUP_DIR/home/minecraft/server"
    rsync -a --backup --backup-dir="$BACKUP_DIR/home/minecraft/server" \
      --exclude systemd --exclude serverconfig \
      "$BUNDLE_DIR/minecraft/" "$SERVER_DIR/"
  else
    warn "rsync is missing; copying without per-file backups"
    cp -a "$BUNDLE_DIR/minecraft/." "$SERVER_DIR/"
    rm -rf "$SERVER_DIR/systemd" "$SERVER_DIR/serverconfig"
  fi
fi

log "installing world/serverconfig"
if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] install -d -o minecraft -g minecraft -m 755 %s/world/serverconfig\n' "$SERVER_DIR"
else
  install -d -o minecraft -g minecraft -m 755 "$SERVER_DIR/world/serverconfig"
fi
for f in "$BUNDLE_DIR"/minecraft/serverconfig/*; do
  [[ -f $f ]] || continue
  install_file "$f" "$SERVER_DIR/world/serverconfig/$(basename "$f")" \
    644 minecraft minecraft
done

# Fabric Loader refuses duplicate mod IDs. The source has several mods
# installed more than once; keep the files faithful but point at the helper.
dupe_families=()
for family in fabric-api ferritecore iris-fabric modmenu sodium-fabric; do
  n=$(find "$BUNDLE_DIR/minecraft/mods" -maxdepth 1 -type f \
        -name "${family}-*.jar" 2>/dev/null | wc -l | tr -d ' ')
  [[ ${n:-0} -gt 1 ]] && dupe_families+=("$family")
done
if [[ ${#dupe_families[@]} -gt 0 ]]; then
  warn "duplicate mod versions in mods/: ${dupe_families[*]}"
  warn "if Fabric refuses to start, run: ./scripts/dedupe-minecraft-mods.sh --apply"
fi

log "server.properties"
if [[ $WITH_SECRETS -eq 1 ]]; then
  copy_secret "$BUNDLE_DIR/secrets/minecraft/server.properties" \
    "$SERVER_DIR/server.properties" 600 minecraft minecraft
  warn "the real management-server-secret is installed; rotate it if you enable the management server"
else
  install_file "$BUNDLE_DIR/minecraft/server.properties" \
    "$SERVER_DIR/server.properties" 644 minecraft minecraft
fi

if [[ $DRY_RUN -eq 0 ]]; then
  chown -R minecraft:minecraft "$SERVER_DIR"
  chmod 755 "$SERVER_DIR/server.jar" "$SERVER_DIR/start.sh"
  chmod 755 "$SERVER_DIR/mods/enable-disable.sh" 2>/dev/null || true
  if [[ -f $SERVER_DIR/server.properties && $WITH_SECRETS -eq 1 ]]; then
    chmod 600 "$SERVER_DIR/server.properties"
  fi
  if ! grep -qi '^eula=true' "$SERVER_DIR/eula.txt" 2>/dev/null; then
    warn "eula.txt does not contain eula=true; the server will refuse to start"
  fi
  if command -v restorecon >/dev/null 2>&1; then
    restorecon -R "$SERVER_DIR" 2>/dev/null \
      || warn "restorecon failed for $SERVER_DIR; Minecraft may not be able to read its files"
  fi
fi

# ---------------------------------------------------------------------------
# systemd unit
# ---------------------------------------------------------------------------

log "installing minecraft.service (heap $MINECRAFT_HEAP)"
unit_tmp=$(mktemp "${TMPDIR:-/tmp}/minecraft-unit.XXXXXX")
sed "s|__MINECRAFT_HEAP__|$MINECRAFT_HEAP|g" \
  "$BUNDLE_DIR/minecraft/systemd/minecraft.service" > "$unit_tmp"
install_file "$unit_tmp" /etc/systemd/system/minecraft.service 644 root root
rm -f "$unit_tmp"

if [[ $DRY_RUN -eq 0 ]]; then
  if command -v restorecon >/dev/null 2>&1; then
    restorecon /etc/systemd/system/minecraft.service 2>/dev/null \
      || warn "restorecon failed for minecraft.service"
  fi
  systemctl daemon-reload
fi
svc_enable minecraft.service

if [[ $START_MINECRAFT -eq 1 ]]; then
  log "starting Minecraft (the first start downloads the vanilla server and Fabric libraries)"
  run systemctl start minecraft.service
  if [[ $DRY_RUN -eq 0 ]]; then
    sleep 2
    systemctl status --no-pager --lines=5 minecraft.service || true
  fi
else
  log "Minecraft is enabled but not started; start it with: systemctl start minecraft"
fi

if ! command -v java >/dev/null 2>&1; then
  warn "java is not on PATH; install a Java runtime before starting Minecraft"
fi

ok "minecraft step complete"
