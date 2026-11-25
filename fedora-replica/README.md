# fedora-replica

A configuration toolkit that recreates the server-side setup of a Fedora home
lab host on a fresh Fedora machine. It reproduces **system configuration**, not
user or world data.

The source host is:

| Item | Value |
| --- | --- |
| OS | Fedora Linux 43 Workstation (x86_64) |
| Kernel | 7.3.3-100.fc43.x86_64 |
| Hardware | Dell OptiPlex 9010, i7-3770, 24 GB RAM |
| Hostname | `fedora` (static hostname was unset) |
| Public name | `noadminabusearda.opik.net` |
| LAN | DHCP `192.168.0.3/24` on `eno1` |
| Role | nginx + Cockpit + Guacamole (Docker) + Fabric Minecraft server |

> **Fedora 43 reaches end of life on 2026-12-02.** A new install will likely be
> Fedora 44 or newer. The bundle does not pin versions; it installs current
> packages and warns about drift. See `inventory/11-differences.md`.

## Layout

```text
fedora-replica/
├── apply.sh                 orchestrator (dry run by default)
├── verify.sh                read-only verification
├── lib.sh                   shared helpers
├── steps/                   one script per subsystem
├── inventory/               what the source looks like, split by topic
│   ├── 01-system.md ... 11-differences.md
│   ├── reference/           fstab, GRUB, broken minecraft.service, ss output
│   └── *.txt                package/unit/port/etc lists
├── etc/                     curated /etc overlay
├── docker/guac-mysql/       redacted compose file + Guacamole schema
├── web/files/               /var/www/files content (without credentials)
├── minecraft/               server jar, mods, configs, serverconfig, unit
├── scripts/                 helper scripts (mod dedupe, manifest)
├── extras/                  optional files not installed by default (ntwrkc)
├── secrets/                 sensitive material (mode 700, read the README)
└── raw/                     collected source output and tarballs (sensitive)
```

Start with `inventory/README.md` for the source description. Read
`inventory/10-exclusions.md` before assuming something is missing, and
`inventory/11-differences.md` before applying.

## Requirements

- A fresh Fedora Server (or Workstation) install with root access.
- Internet access for `dnf`, Docker image pulls and the first Minecraft start.
- At least 20 GB free disk; 5 GB is the hard minimum for packages and images.
- For the default Minecraft heap, more than 18 GB RAM. On a smaller host pass
  `--minecraft-heap 4G` (or similar).
- Ports 80 and 443 reachable from the Internet if you want Let's Encrypt
  renewal with the HTTP-01 challenge.
- DNS for the chosen domain pointing at the target.

## Quick start

```bash
cd fedora-replica

# 1. Inspect what would happen. Nothing is changed.
sudo ./apply.sh

# 2. Apply with the source secrets and the real Minecraft properties.
sudo ./apply.sh --apply --yes --with-secrets

# 3. Check the result.
sudo ./verify.sh
```

Without `--with-secrets` the run still works, but:

- nginx gets a self-signed placeholder certificate;
- the Guacamole stack gets random database passwords in
  `/home/andrey/guac-mysql/.env`;
- `server.properties` gets `management-server-secret=CHANGE_ME`;
- CoolerControl has no login password or custom certificate.

The default mode is a **dry run**. `--apply` is required to change anything.
Every replaced file is copied to `/var/backups/fedora-replica-<timestamp>/`
before it is overwritten.

## Common invocations

```bash
# Full replica, existing certificate and secrets
sudo ./apply.sh --apply --yes --with-secrets

# New domain and a new certificate
sudo ./apply.sh --apply --yes \
  --domain lab.example.com \
  --email admin@example.com \
  --certbot

# Smaller host: 4 GB Minecraft heap, no CoolerControl, no PCP
sudo ./apply.sh --apply --yes --with-secrets \
  --minecraft-heap 4G --skip-coolercontrol --skip-pcp

# Only packages, system identity and users
sudo ./apply.sh --apply --only 10,20,30

# Web stack and everything after it
sudo ./apply.sh --apply --from 50

# Re-run one step after fixing a problem
sudo ./apply.sh --apply --only 50
```

### Flags

| Flag | Meaning |
| --- | --- |
| `--apply` | Execute. Without it everything is a dry run. |
| `--yes` | Do not ask for confirmation. |
| `--with-secrets` | Install `secrets/` material. |
| `--certbot` | Issue a certificate after nginx is up. |
| `--email ADDRESS` | ACME email for `--certbot`. |
| `--set-passwords` | Set `andrey`'s password from `secrets/`. |
| `--domain DOMAIN` | Public DNS name. Default `noadminabusearda.opik.net`. |
| `--hostname NAME` | Static hostname. Default `fedora`. |
| `--nextcloud-upstream URL` | Upstream for `nextcloud.<domain>`. |
| `--minecraft-heap SIZE` | Java `-Xmx`, default `18G`. |
| `--start-minecraft` | Start Minecraft at the end (first start downloads). |
| `--all-users` | Also create `mom` and `ml`. |
| `--skip-coolercontrol` | Skip step 70. |
| `--skip-docker` | Skip step 80. |
| `--skip-minecraft` | Skip step 90. |
| `--skip-pcp` | Do not enable PCP. |
| `--skip-libvirt` | Do not install libvirt/virt-install. |
| `--only LIST` | Run only the listed step prefixes. |
| `--from N` | Run steps with prefix >= N. |
| `--list-steps` | Print the step list. |

## What each step does

| Step | Actions |
| --- | --- |
| `00-preflight.sh` | Checks Fedora, root, disk, RAM, network and bundle integrity; refuses to run on the source (machine-id check). |
| `10-packages.sh` | Installs nginx, certbot, firewalld, Cockpit, Docker, Java, tuning/monitoring, PCP, libvirt, utilities. Falls back if a package name has changed. |
| `20-system.sh` | Hostname, timezone `America/New_York`, locale, `throughput-performance`, SELinux booleans, dnf timer, `multi-user.target`, tlog, sensors, Samba config, NFS exports file. |
| `30-users.sh` | Creates `andrey` (wheel, docker) and `minecraft`; optionally `mom` and `ml`; sets `andrey`'s password with `--set-passwords`. |
| `40-firewall.sh` | Installs the `FedoraWorkstation` zone, `docker` zone and `docker-forwarding` policy; sets the default zone; opens the source's service/port set. |
| `50-nginx.sh` | Renders nginx sites with the chosen domain/upstream, installs `/var/www/files`, installs or creates TLS material, runs `nginx -t`, enables nginx, optionally issues a certificate. |
| `60-cockpit.sh` | Installs `cockpit.conf` and enables `cockpit.socket` on 9090. |
| `70-coolercontrol.sh` | Enables the COPR, installs CoolerControl, copies its config (and password/cert with secrets). |
| `80-docker.sh` | Enables Docker, creates `/home/andrey/guac-mysql`, installs compose + schema, starts the stack, imports the schema if empty, waits for the UI. |
| `90-minecraft.sh` | Copies the Fabric server jar, mods, configs, Dynmap configs and world/serverconfig; installs a working `minecraft.service`; enables it. |
| `95-services.sh` | Enables/starts the server units and timers; reports failed units. |
| `99-summary.sh` | Prints ports, service state, web endpoints and the post-install checklist. |

## Security notes

The bundle is faithful to the source but fixes a few dangerous things:

1. **The Guacamole compose file with credentials is not published under
   `/var/www/files`.** The source served it publicly through nginx
   `autoindex on`. Only `initdb.sql` is published.
2. **`server.properties` is redacted by default.** The real
   `management-server-secret` is only installed with `--with-secrets`.
3. **`/etc/shadow`, SSH host keys and Cockpit certificates are not copied.**
4. **The broken `minecraft.service` is replaced** with a working unit.
5. **`apply.sh` backs up replaced files** instead of deleting them.

Things that remain risky on purpose (for fidelity):

- The `FedoraWorkstation` firewalld zone allows **all TCP/UDP ports
  1025-65535**. Narrow it if the target is Internet-facing.
- `/var/www/files` is served with `autoindex on`. It contains the Guacamole
  schema, which is not secret, but review what you put there.
- The source `homelab.conf` has a typo (`$http_update` instead of
  `$http_upgrade`) that can break Guacamole WebSocket upgrades.
- `nextcloud.<domain>` has no certificate that covers its own name.
- The `mods/enable-disable.sh` helper is syntactically broken.
- The 45Drives repo is broken; `cockpit-file-sharing` is not installed.
- Minecraft has duplicate mod versions; Fabric may refuse to start until you
  run `scripts/dedupe-minecraft-mods.sh --apply`.

Read `inventory/11-differences.md` for the full list.

## Verification

`verify.sh` is read-only and prints `PASS`/`FAIL`/`WARN` for:

- Fedora, timezone, SELinux, tuned;
- users and group membership;
- packages and commands;
- active/enabled services;
- listening ports (22, 80, 443, 8080, 9090, 25565);
- `nginx -t` and TLS certificate validity/self-signed status;
- firewalld default zone and allowed services;
- three Guacamole containers and the web endpoint;
- Minecraft unit, jar, EULA, mods, serverconfig and ownership;
- secret file permissions and the accidental exposure of the compose file.

Exit status is `1` if any check fails. Warnings do not fail the run.

## Post-install checklist

1. Change the Guacamole admin password (default `guacadmin` / `guacadmin`).
2. Set `andrey`'s password if you did not use `--set-passwords`.
3. Issue a real certificate if nginx is using the placeholder.
4. Give the target a DHCP reservation or static address.
5. Narrow the firewall if the host is Internet-facing.
6. Review `/var/www/files` exposure.
7. Start Minecraft (`systemctl start minecraft`) if you did not use
   `--start-minecraft`; the first start downloads the vanilla server and
   Fabric libraries.
8. If Minecraft reports duplicate mod IDs, run
   `sudo ./scripts/dedupe-minecraft-mods.sh --apply`.
9. Recreate Guacamole connections/users or restore a database dump.
10. Configure backups for the Minecraft world, the MySQL volume and
    `/etc/letsencrypt`.

## Re-running and backups

`apply.sh` is idempotent where possible:

- packages are only installed if missing;
- config files are compared before replacement;
- users/groups are created only if missing;
- the Guacamole schema is imported only if `guacamole_db` has no tables;
- Minecraft files are copied over existing ones, but world data is never
  deleted.

Each `--apply` creates a new backup directory. To roll back a single file:

```bash
sudo cp -a /var/backups/fedora-replica-<timestamp>/etc/nginx/conf.d/homelab.conf \
          /etc/nginx/conf.d/homelab.conf
sudo systemctl reload nginx
```

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `nginx -t` fails after step 50 | Certificate paths missing. Re-run step 50 with `--with-secrets`, `--certbot`, or let it create the placeholder. |
| Guacamole container restarts | MySQL not ready or schema mismatch. Check `docker logs guac-mysql` and `docker logs guacamole`; pin image tags if the schema is too old. |
| `guacamole_db` has no tables | `docker exec ... mysql ... < initdb.sql` failed. Run the import manually, then restart `guacamole`. |
| Minecraft exits with duplicate mod ID | `sudo ./scripts/dedupe-minecraft-mods.sh --apply`. |
| Minecraft exits immediately | Check `journalctl -u minecraft` and `/home/minecraft/server/logs/latest.log`. The first start needs Internet access. |
| `mcelog`/`thermald` fail | Expected on VMs and unsupported hardware. Disable them if you do not need them. |
| CoolerControl fails | It needs supported sensors. Skip with `--skip-coolercontrol`. |
| `firewall-cmd --reload` fails | The `docker` zone/policy may not exist before Docker is installed; re-run step 40 after step 10. |
| Certificate renewal fails | DNS must point at the target and ports 80/443 must be reachable. Check `certbot renew --dry-run`. |
| `certbot` refuses to replace the placeholder lineage | Remove `/etc/letsencrypt/{live,archive,renewal}/<domain>` and re-run `--certbot`. nginx will not reload until the new certificate exists, so do this in one maintenance window. |
| `dnf` cannot find `moby-engine` | A newer Fedora may have renamed it. Install `docker` and re-run step 80. |

## Sensitive files

- `secrets/` - mode `700`; read `secrets/README.md` before using it.
- `raw/` - collected source output, including `raw/etc.tar.gz` (full `/etc`,
  shadow, host keys, TLS keys) and `raw/minecraft.tar.gz` (mods and configs).
  Both are mode `600`. **Do not distribute `raw/` or `secrets/`.**
- `MANIFEST.sha256` covers the non-secret, non-raw bundle.
  `secrets/SHA256SUMS` covers the secret files. Verify them from the bundle
  root:

  ```bash
  sha256sum -c MANIFEST.sha256
  sha256sum -c secrets/SHA256SUMS
  # macOS: shasum -a 256 -c ...
  ```

## Source inventory

The `inventory/` directory is the authoritative description of the source:

| File | Topic |
| --- | --- |
| `01-system.md` | OS, hardware, hostname, time, tuned, SELinux |
| `02-packages.md` | repositories, curated package set, version drift |
| `03-services.md` | enabled units, ports, service notes |
| `04-network.md` | interfaces, DHCP, Wi-Fi, firewalld, Docker networking |
| `05-storage.md` | btrfs/ext4 layout, fstab, zram, trim |
| `06-users.md` | users, groups, UIDs, password handling |
| `07-web.md` | nginx, TLS, Cockpit, certbot, `/var/www/files` |
| `08-docker.md` | Docker engine and Guacamole |
| `09-minecraft.md` | Fabric server, mods, configs, exclusions |
| `10-exclusions.md` | everything deliberately not copied |
| `11-differences.md` | hardware/version caveats and known quirks |
