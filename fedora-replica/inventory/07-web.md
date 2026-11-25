# 07 - Web stack

## nginx

`/etc/nginx/nginx.conf` is the stock Fedora file: `user nginx`, `worker_processes
auto`, `include /etc/nginx/conf.d/*.conf`, default server on port 80. No
changes were made to it.

Custom files:

| File | Purpose |
| --- | --- |
| `/etc/nginx/conf.d/cockpit.conf` | `cockpit.<domain>` -> `https://127.0.0.1:9090/` |
| `/etc/nginx/conf.d/homelab.conf` | `<domain>` home page, `/guac/`, `/bluemap/`, `/files/` |
| `/etc/nginx/conf.d/nextcloud.conf` | `nextcloud.<domain>` -> `http://192.168.0.4:8080` |
| `/etc/nginx/sites-available/cockpit` | stale old-domain config, not included |

### `<domain>` site (`homelab.conf`)

- `location = /` returns an inline HTML page titled "SigmaCentral" with links
  to Guacamole, Cockpit, BlueMap, CentralSigma and Nextcloud.
- `location /guac/` proxies to `http://localhost:8080/guacamole/` with
  buffering off and WebSocket headers. The source has a typo:
  `proxy_set_header Upgrade $http_update;` (should be `$http_upgrade`) and
  `Connection $http_connection`. It works for normal HTTP; WebSocket upgrades
  may be unreliable. The replica preserves the file faithfully.
- `location /bluemap/` proxies to `http://127.0.0.1:8100/`. BlueMap is
  currently disabled (`.jar.disabled`), so this returns 502 until enabled.
- `location /files/` serves `/var/www/files/` with `autoindex on`.
- Port 80 redirects to HTTPS, then returns 404 for unknown hosts.
- TLS certificate paths are hard-coded to
  `/etc/letsencrypt/live/noadminabusearda.opik.net/`.

### Cockpit site

`cockpit.<domain>` proxies to Cockpit's TLS listener on `127.0.0.1:9090` with
`proxy_ssl_verify off`. Port 80 redirects to HTTPS.

`/etc/cockpit/cockpit.conf` allows the origins:

```ini
[WebService]
Origins = https://cockpit.noadminabusearda.opik.net https://localhost:9090
ProtocolHeader = X-Forwarded-Proto
```

### Nextcloud site

`nextcloud.<domain>` proxies to `http://192.168.0.4:8080` (a different LAN
host). Port 80 redirects to HTTPS. The 443 block has no explicit
`ssl_certificate`; it inherits the default certificate, which does **not**
cover `nextcloud.<domain>` (the Let's Encrypt certificate only lists
`noadminabusearda.opik.net` and `cockpit.noadminabusearda.opik.net`). Expect a
certificate-name mismatch unless you issue a separate certificate. The
upstream address is parameterized as `NEXTCLOUD_UPSTREAM` in `apply.sh`.

## TLS / Let's Encrypt

- Certificate name: `noadminabusearda.opik.net`
- Key type: ECDSA
- Identifiers: `noadminabusearda.opik.net`, `cockpit.noadminabusearda.opik.net`
- Expiry: **2027-02-07 19:37:17 UTC**
- Renewal: `certbot-renew.timer`, authenticator/installer `nginx`
- Account: `a9954c528c8819240b68564fb90f3746`
- Files: `/etc/letsencrypt/{live,archive,renewal,accounts}`

The full `/etc/letsencrypt` tree is in `../secrets/letsencrypt/` because it
contains private keys and the ACME account key. `apply.sh --with-secrets`
copies it to `/etc/letsencrypt` and sets the archive/account directories to
`700` and the private keys to `600` (certificates and renewal configs are
world-readable, as certbot expects). Without it, step 50 creates a
self-signed placeholder at the expected paths so `nginx -t` still passes and
nginx can start.

If you use a different domain, do not reuse this certificate. Issue a new one:

```bash
certbot --nginx -d "$TARGET_DOMAIN" -d "cockpit.$TARGET_DOMAIN"
```

Ports 80 and 443 must be reachable from the Internet for the HTTP-01
challenge, and DNS must point at the target.

## certbot

- `certbot` 5.7.0 and `python3-certbot-nginx` 5.7.0
- `/etc/letsencrypt/cli.ini` only sets `preconfigured-renewal = True` and
  `max-log-backups = 0`
- `certbot-renew.timer` is enabled

## Cockpit

- `cockpit.socket` listens on `*:9090` (TLS).
- Packages: `cockpit`, `cockpit-files`, `cockpit-networkmanager`,
  `cockpit-packagekit`, `cockpit-storaged`, `cockpit-system`,
  `cockpit-machines`, `cockpit-session-recording`.
- `/etc/cockpit/cockpit.conf` is the only custom file.
- Self-signed Cockpit certificates in `/etc/cockpit/ws-certs.d/` are **not**
  copied; Cockpit regenerates them on first start.
- `cockpit-file-sharing` was installed from the now-broken 45Drives repo and
  is not reproduced.

## `/var/www/files`

The source directory contains:

| Path | Size | Contents |
| --- | --- | --- |
| `/var/www/files/cockpit.conf` | 947 B | copy of the Cockpit nginx site |
| `/var/www/files/homelab.conf` | 1671 B | older copy of the homelab site |
| `/var/www/files/docker/guac-mysql/initdb.sql` | 23 KB | Guacamole schema |
| `/var/www/files/docker/guac-mysql/docker-compose.yml` | 881 B | compose file **with credentials** |
| `/var/www/files/server.tar.gz` | 5.17 GB | full server backup - **data, excluded** |

Because `autoindex on` exposes this directory, the source publicly served its
Guacamole database password. The replica installs only the two nginx config
copies and `initdb.sql`; it does **not** publish the compose file with
credentials or the 5 GB tarball. This is a deliberate security divergence.

## Web verification

```bash
nginx -t
curl -kI https://127.0.0.1/            # default site (Host: <domain>)
curl -kI https://127.0.0.1/guac/       # Guacamole via nginx
curl -kI https://127.0.0.1:9090/       # Cockpit directly
openssl x509 -in /etc/letsencrypt/live/<domain>/fullchain.pem -noout -dates
```
