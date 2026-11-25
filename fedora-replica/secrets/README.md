# Secrets

This directory contains the sensitive material extracted from the source host.
It is mode `700`; every file is mode `600` in the bundle. **Do not commit,
publish or email this directory.**

`apply.sh` installs these files only when you pass `--with-secrets`. Without
that flag it uses the redacted templates and generates fresh passwords where it
can.

## Contents

| Path | What it is | Installed to |
| --- | --- | --- |
| `system/andrey-password.txt` | The source `andrey` login password | used by `--set-passwords`, not copied as a file |
| `docker/guac-mysql/docker-compose.yml` | Guacamole compose file with hard-coded MySQL root and `guacuser` passwords | `/home/andrey/guac-mysql/docker-compose.yml` |
| `minecraft/server.properties` | Real server properties, including `management-server-secret` | `/home/minecraft/server/server.properties` |
| `minecraft/mail/msmtprc` | SMTP credentials for Minecraft server mail | not installed automatically; copy to `/home/minecraft/.msmtprc` if needed |
| `minecraft/mail/muttrc` | Mutt configuration matching `msmtprc` | not installed automatically; copy to `/home/minecraft/.muttrc` if needed |
| `NetworkManager/BESThome.nmconnection` | Wi-Fi profile with WPA PSK | `/etc/NetworkManager/system-connections/` (manual) |
| `NetworkManager/wireless.nmconnection` | Hidden Wi-Fi profile with WPA PSK | `/etc/NetworkManager/system-connections/` (manual) |
| `coolercontrol/passwd` | Argon2 hash of the CoolerControl login password | `/etc/coolercontrol/.passwd` |
| `coolercontrol/coolercontrol.key` | CoolerControl self-signed TLS private key | `/etc/coolercontrol/coolercontrol.key` |
| `coolercontrol/coolercontrol.crt` | CoolerControl self-signed certificate | `/etc/coolercontrol/coolercontrol.crt` |
| `letsencrypt/` | Full Let's Encrypt state: account key, archive, live symlinks, renewal config | `/etc/letsencrypt/` |

## What is not here

- `/etc/shadow` and `/etc/gshadow` - not copied at all.
- SSH host keys - the target generates new ones.
- Cockpit self-signed certificates - regenerated on first start.
- The Guacamole MySQL data volume - database contents, not configuration.
- The 5.17 GB `server.tar.gz` backups.
- Minecraft world/player data.

## Rotation checklist

Assume every value in this directory is compromised if the bundle was ever
stored or shared insecurely. Before exposing the target to the Internet:

1. Change the `andrey` password (`passwd andrey`).
2. Change the Guacamole `guacadmin` password after first login.
3. Change the MySQL root and `guacuser` passwords, or let `apply.sh` generate
   new ones by omitting `--with-secrets`.
4. Regenerate `management-server-secret` if you enable the Minecraft
   management server.
5. Reissue the Let's Encrypt certificate rather than reusing the archived key
   (`certbot --nginx -d <domain> -d cockpit.<domain> --force-renewal`).
6. Change the CoolerControl password and regenerate its certificate.
7. Re-key the Wi-Fi networks or edit the PSKs in the `.nmconnection` files.
8. Replace the SMTP credentials in `.msmtprc`.

The Let's Encrypt ACME account key (`accounts/.../private_key.json`) can issue
certificates for any domain on that account. Revoke or rotate it if the bundle
leaks.
