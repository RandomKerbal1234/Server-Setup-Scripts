#!/usr/bin/env bash
# 80-docker.sh - Docker engine and the Guacamole stack.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

PROJECT_DIR=/home/andrey/guac-mysql
ROOT_PW=""

strip_quotes() {
  local v=$1
  v=${v%\"}; v=${v#\"}
  v=${v%\'}; v=${v#\'}
  printf '%s' "$v"
}

compose_root_pw() {
  local file=$1
  strip_quotes "$(sed -n 's/^[[:space:]]*MYSQL_ROOT_PASSWORD:[[:space:]]*//p' "$file" | head -1)"
}

env_root_pw() {
  local file=$1
  strip_quotes "$(sed -n 's/^MYSQL_ROOT_PASSWORD=//p' "$file" | head -1)"
}

if ! id andrey >/dev/null 2>&1; then
  die "user andrey does not exist; run step 30 first"
fi

if ! command -v docker >/dev/null 2>&1 && [[ $DRY_RUN -eq 0 ]]; then
  warn "docker is not installed; skipping the Guacamole stack"
  exit 0
fi

log "enabling Docker"
svc_enable_now docker.socket
svc_enable_now docker.service

if [[ $DRY_RUN -eq 0 ]]; then
  docker info >/dev/null 2>&1 || die "cannot talk to the Docker daemon"
  if getent group docker >/dev/null 2>&1; then
    usermod -aG docker andrey
  else
    warn "docker group not found; add andrey to it manually"
  fi
fi

log "creating $PROJECT_DIR"
if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] install -d -o andrey -g andrey -m 755 %s\n' "$PROJECT_DIR"
else
  install -d -o andrey -g andrey -m 755 "$PROJECT_DIR"
  chown andrey:andrey "$PROJECT_DIR"
fi

install_file "$BUNDLE_DIR/docker/guac-mysql/initdb.sql" \
  "$PROJECT_DIR/initdb.sql" 644 andrey andrey

if [[ $WITH_SECRETS -eq 1 ]]; then
  log "installing the source compose file with its credentials"
  copy_secret "$BUNDLE_DIR/secrets/docker/guac-mysql/docker-compose.yml" \
    "$PROJECT_DIR/docker-compose.yml" 600 andrey andrey
  if [[ $DRY_RUN -eq 0 ]]; then
    ROOT_PW=$(compose_root_pw "$PROJECT_DIR/docker-compose.yml")
    [[ -n $ROOT_PW ]] || die "could not read MYSQL_ROOT_PASSWORD from $PROJECT_DIR/docker-compose.yml"
  else
    ROOT_PW="<from secrets>"
  fi
else
  log "installing the redacted compose file and generating passwords"
  install_file "$BUNDLE_DIR/docker/guac-mysql/docker-compose.yml" \
    "$PROJECT_DIR/docker-compose.yml" 600 andrey andrey
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] create %s/.env with random MYSQL_ROOT_PASSWORD and GUAC_MYSQL_PASSWORD\n' "$PROJECT_DIR"
    ROOT_PW="<generated>"
  elif [[ -f $PROJECT_DIR/.env ]]; then
    log "reusing the existing $PROJECT_DIR/.env"
    ROOT_PW=$(env_root_pw "$PROJECT_DIR/.env")
    [[ -n $ROOT_PW ]] || die "$PROJECT_DIR/.env exists but MYSQL_ROOT_PASSWORD is empty"
    if ! grep -q '^GUAC_MYSQL_PASSWORD=.' "$PROJECT_DIR/.env"; then
      die "$PROJECT_DIR/.env exists but GUAC_MYSQL_PASSWORD is empty"
    fi
  else
    ROOT_PW=$(rand_password)
    GUAC_PW=$(rand_password)
    (
      umask 077
      printf 'MYSQL_ROOT_PASSWORD=%s\nGUAC_MYSQL_PASSWORD=%s\n' "$ROOT_PW" "$GUAC_PW" \
        > "$PROJECT_DIR/.env"
    )
    chown andrey:andrey "$PROJECT_DIR/.env"
    chmod 600 "$PROJECT_DIR/.env"
    ok "generated $PROJECT_DIR/.env"
  fi
fi

# ---------------------------------------------------------------------------
# Compose
# ---------------------------------------------------------------------------

if [[ $DRY_RUN -eq 1 ]]; then
  COMPOSE=(docker compose)
elif docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die "neither 'docker compose' nor 'docker-compose' is available"
fi

log "starting the stack (this may pull several GB of images)"
run "${COMPOSE[@]}" -p guac-mysql --project-directory "$PROJECT_DIR" \
  -f "$PROJECT_DIR/docker-compose.yml" up -d

# ---------------------------------------------------------------------------
# Wait for MySQL and initialize the schema
# ---------------------------------------------------------------------------

if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] wait for guac-mysql, then import initdb.sql if the schema is empty\n'
else
  log "waiting for guac-mysql"
  mysql_ready=0
  for _ in $(seq 1 60); do
    if docker exec -e MYSQL_PWD="$ROOT_PW" guac-mysql \
         mysqladmin ping -h 127.0.0.1 -uroot --silent >/dev/null 2>&1; then
      mysql_ready=1
      break
    fi
    sleep 2
  done
  [[ $mysql_ready -eq 1 ]] || die "guac-mysql did not become ready in 120 seconds"

  table_count=$(docker exec -e MYSQL_PWD="$ROOT_PW" guac-mysql \
    mysql -uroot -N -B -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='guacamole_db';" \
    2>/dev/null || echo 0)

  if [[ ${table_count:-0} -eq 0 ]]; then
    log "importing the Guacamole schema"
    docker exec -i -e MYSQL_PWD="$ROOT_PW" guac-mysql \
      mysql -uroot guacamole_db < "$PROJECT_DIR/initdb.sql"
    ok "schema imported (default login guacadmin / guacadmin)"
    run "${COMPOSE[@]}" -p guac-mysql --project-directory "$PROJECT_DIR" \
      -f "$PROJECT_DIR/docker-compose.yml" restart guacamole
  else
    log "guacamole_db already has $table_count tables; not importing initdb.sql"
  fi

  log "container status"
  docker ps --filter name=guac --format '    {{.Names}}  {{.Status}}  {{.Ports}}' || true
fi

# ---------------------------------------------------------------------------
# Wait for the web UI
# ---------------------------------------------------------------------------

if [[ $DRY_RUN -eq 0 ]]; then
  guac_up=0
  for _ in $(seq 1 60); do
    if curl -fsS -o /dev/null --max-time 5 http://127.0.0.1:8080/guacamole/ 2>/dev/null; then
      guac_up=1
      break
    fi
    sleep 2
  done
  if [[ $guac_up -eq 1 ]]; then
    ok "Guacamole responds on http://127.0.0.1:8080/guacamole/"
  else
    warn "Guacamole did not respond yet; check 'docker logs guacamole'"
  fi
fi

warn "the default Guacamole login is guacadmin / guacadmin; change it immediately"
ok "docker step complete"
