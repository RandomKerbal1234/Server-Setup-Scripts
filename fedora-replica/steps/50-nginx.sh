#!/usr/bin/env bash
# 50-nginx.sh - nginx sites, /var/www/files and TLS.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

LE_LIVE="/etc/letsencrypt/live/$DOMAIN"
PLACEHOLDER_CREATED=0
SOURCE_CERT_AVAILABLE=0

# ---------------------------------------------------------------------------
# Public certbot option files (not secret)
# ---------------------------------------------------------------------------

log "certbot TLS option files"
install_file "$BUNDLE_DIR/etc/letsencrypt-options/options-ssl-nginx.conf" \
  /etc/letsencrypt/options-ssl-nginx.conf 644 root root
install_file "$BUNDLE_DIR/etc/letsencrypt-options/ssl-dhparams.pem" \
  /etc/letsencrypt/ssl-dhparams.pem 644 root root

# ---------------------------------------------------------------------------
# nginx site configuration
# ---------------------------------------------------------------------------

log "installing nginx site configuration"
install_template "$BUNDLE_DIR/etc/nginx/conf.d/cockpit.conf" \
  /etc/nginx/conf.d/cockpit.conf 644 root root
install_template "$BUNDLE_DIR/etc/nginx/conf.d/homelab.conf" \
  /etc/nginx/conf.d/homelab.conf 644 root root
install_template "$BUNDLE_DIR/etc/nginx/conf.d/nextcloud.conf" \
  /etc/nginx/conf.d/nextcloud.conf 644 root root
install_file "$BUNDLE_DIR/etc/nginx/sites-available/cockpit" \
  /etc/nginx/sites-available/cockpit 644 root root

# ---------------------------------------------------------------------------
# TLS material
# ---------------------------------------------------------------------------

log "TLS material for $DOMAIN"
if [[ $WITH_SECRETS -eq 1 && $DOMAIN == "$SOURCE_DOMAIN" && \
      -f "$BUNDLE_DIR/secrets/letsencrypt/live/$SOURCE_DOMAIN/fullchain.pem" ]]; then
  SOURCE_CERT_AVAILABLE=1
  log "installing the source Let's Encrypt tree (--with-secrets)"
  if [[ -d /etc/letsencrypt ]]; then
    backup_path /etc/letsencrypt
  fi
  copy_tree "$BUNDLE_DIR/secrets/letsencrypt" /etc/letsencrypt
  if [[ $DRY_RUN -eq 0 ]]; then
    chown -R root:root /etc/letsencrypt
    chmod 755 /etc/letsencrypt
    chmod 700 /etc/letsencrypt/accounts /etc/letsencrypt/archive \
              "/etc/letsencrypt/archive/$SOURCE_DOMAIN"
    chmod 755 /etc/letsencrypt/live "/etc/letsencrypt/live/$SOURCE_DOMAIN" \
              /etc/letsencrypt/renewal
    find "/etc/letsencrypt/archive/$SOURCE_DOMAIN" -name 'privkey*.pem' -exec chmod 600 {} +
    find "/etc/letsencrypt/archive/$SOURCE_DOMAIN" -type f ! -name 'privkey*.pem' -exec chmod 644 {} +
    find /etc/letsencrypt/accounts -name private_key.json -exec chmod 600 {} +
    find /etc/letsencrypt/accounts -type f ! -name private_key.json -exec chmod 644 {} +
    chmod 644 /etc/letsencrypt/cli.ini /etc/letsencrypt/options-ssl-nginx.conf \
              /etc/letsencrypt/ssl-dhparams.pem 2>/dev/null || true
    find /etc/letsencrypt/renewal -type f -exec chmod 644 {} +
  fi
elif [[ $WITH_SECRETS -eq 1 && $DOMAIN != "$SOURCE_DOMAIN" ]]; then
  warn "skipping the bundled certificate: it is for $SOURCE_DOMAIN, not $DOMAIN"
fi

if [[ $SOURCE_CERT_AVAILABLE -eq 0 && ! -f "$LE_LIVE/fullchain.pem" ]]; then
  log "no certificate for $DOMAIN; creating a self-signed placeholder"
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] openssl req -x509 ... -subj /CN=%s\n' "$DOMAIN"
  else
    mkdir -p "/etc/letsencrypt/archive/$DOMAIN" "$LE_LIVE" /etc/letsencrypt/renewal
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -subj "/CN=$DOMAIN" \
      -keyout "/etc/letsencrypt/archive/$DOMAIN/privkey1.pem" \
      -out "/etc/letsencrypt/archive/$DOMAIN/fullchain1.pem" >/dev/null 2>&1
    cp -f "/etc/letsencrypt/archive/$DOMAIN/fullchain1.pem" \
          "/etc/letsencrypt/archive/$DOMAIN/cert1.pem"
    cp -f "/etc/letsencrypt/archive/$DOMAIN/fullchain1.pem" \
          "/etc/letsencrypt/archive/$DOMAIN/chain1.pem"
    ln -sfn "../../archive/$DOMAIN/privkey1.pem"   "$LE_LIVE/privkey.pem"
    ln -sfn "../../archive/$DOMAIN/fullchain1.pem" "$LE_LIVE/fullchain.pem"
    ln -sfn "../../archive/$DOMAIN/cert1.pem"      "$LE_LIVE/cert.pem"
    ln -sfn "../../archive/$DOMAIN/chain1.pem"     "$LE_LIVE/chain.pem"
    chmod 644 "/etc/letsencrypt/archive/$DOMAIN/"*.pem
    chmod 600 "/etc/letsencrypt/archive/$DOMAIN/privkey1.pem"
    chmod 700 /etc/letsencrypt/archive "/etc/letsencrypt/archive/$DOMAIN"
    chmod 755 "$LE_LIVE"
    PLACEHOLDER_CREATED=1
    warn "self-signed certificate installed; browsers will warn until a real certificate is issued"
  fi
else
  log "using the existing certificate at $LE_LIVE"
fi

# ---------------------------------------------------------------------------
# /var/www/files
# ---------------------------------------------------------------------------

log "populating /var/www/files"
ensure_dir /var/www/files 755
ensure_dir /var/www/files/docker/guac-mysql 755
install_template "$BUNDLE_DIR/web/files/cockpit.conf" \
  /var/www/files/cockpit.conf 644 root root
install_template "$BUNDLE_DIR/web/files/homelab.conf" \
  /var/www/files/homelab.conf 644 root root
install_file "$BUNDLE_DIR/docker/guac-mysql/initdb.sql" \
  /var/www/files/docker/guac-mysql/initdb.sql 644 root root
# Deliberately not installed: the compose file with credentials and the 5 GB
# server.tar.gz. See inventory/07-web.md.

# ---------------------------------------------------------------------------
# nginx
# ---------------------------------------------------------------------------

if [[ $DRY_RUN -eq 0 ]] && command -v restorecon >/dev/null 2>&1; then
  log "restoring SELinux contexts for nginx and TLS"
  restorecon -R /etc/nginx /etc/letsencrypt /var/www/files 2>/dev/null \
    || warn "restorecon failed; nginx may not be able to read its files"
fi

log "testing nginx configuration"
if [[ $DRY_RUN -eq 0 ]]; then
  nginx -t || die "nginx -t failed; fix the configuration before continuing"
else
  printf '    [dry-run] nginx -t\n'
fi

svc_enable_now nginx

# ---------------------------------------------------------------------------
# Optional: issue a new certificate
# ---------------------------------------------------------------------------

if [[ $CERTBOT -eq 1 ]]; then
  log "requesting a Let's Encrypt certificate for $DOMAIN and cockpit.$DOMAIN"
  if ! command -v certbot >/dev/null 2>&1; then
    warn "certbot is not installed; skipping certificate issuance"
  else
    certbot_args=(certonly --nginx -d "$DOMAIN" -d "cockpit.$DOMAIN"
                  --cert-name "$DOMAIN" --non-interactive --agree-tos)
    if [[ -n $CERTBOT_EMAIL ]]; then
      certbot_args+=(--email "$CERTBOT_EMAIL")
    else
      certbot_args+=(--register-unsafely-without-email)
    fi
    if [[ $PLACEHOLDER_CREATED -eq 1 ]]; then
      certbot_args+=(--force-renewal)
    else
      certbot_args+=(--keep-until-expiring)
    fi
    if run certbot "${certbot_args[@]}"; then
      if [[ $DRY_RUN -eq 1 ]]; then
        printf '    [dry-run] install /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh\n'
        printf '    [dry-run] systemctl reload nginx\n'
      else
        ok "certificate issued for $DOMAIN"
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        printf '%s\n' '#!/bin/sh' 'systemctl reload nginx 2>/dev/null || true' \
          > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
        chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
        systemctl reload nginx
      fi
    else
      warn "certbot failed; the self-signed placeholder remains in place"
    fi
  fi
else
  log "not issuing a certificate (pass --certbot to do it now)"
fi

ok "nginx step complete"
