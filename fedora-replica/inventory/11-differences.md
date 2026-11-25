# 11 - Differences, caveats and things that cannot be copied

## The source is about to be EOL

Fedora 43 support ends **2026-12-02**. A new install today will be Fedora 44 or
newer. Consequences:

- Package versions in `packages-relevant.txt` are a snapshot, not pins.
- Some package names change over time (`dnf5-plugin-automatic`,
  `java-25-openjdk-headless`, `moby-engine`). `steps/10-packages.sh` falls back
  to alternatives and warns instead of failing the whole run.
- Defaults change between releases. In particular, Fedora Server and Workstation
  ship different firewalld defaults; the replica explicitly sets the
  `FedoraWorkstation` zone to match the source.
- The source is a **Workstation** install. The replica targets
  `multi-user.target` and does not install GNOME, GDM, Bluetooth, printing,
  Avahi, ModemManager, ABRT, VirtualBox guest tools or desktop apps.

## Hardware-specific

| Item | Why it cannot be copied | What to do |
| --- | --- | --- |
| Disk UUIDs / btrfs layout | tied to `sda` on the source | create the same subvolume layout on the target, keep its UUIDs |
| `/etc/fstab` | UUIDs and partition sizes | use `reference/fstab` as a template only |
| `/etc/default/grub`, `/etc/kernel/cmdline` | bootloader entries are machine-specific | keep the target's bootloader config |
| Machine ID | must be unique | target generates its own |
| SSH host keys | must be unique per host | target generates new keys |
| Cockpit self-signed certs | generated on first start | Cockpit regenerates |
| CoolerControl certificate | self-signed, tied to the old install | included in secrets, or let CoolerControl generate new |
| CoolerControl sensor calibration | depends on fans/sensors | `calibrations.json` copied but may not match new hardware |
| Wi-Fi profiles | interface name `wlp2s0`, PSKs | edit `interface-name`; wired server does not need them |
| NVIDIA / Steam / Chrome repos | desktop GPU/software | not applied |
| Dell firmware A13 | 2013 firmware | update separately if needed |
| 24 GB RAM | Minecraft heap is 18 GB | pass `--minecraft-heap 4G` on a smaller host |

## Network-specific

- The source is DHCP on `eno1` with a reservation at `192.168.0.3`. The replica
  does not force an address. Configure DHCP reservation or a static profile.
- The firewall opens **all ports 1025-65535**. This is reproduced for fidelity
  but is a security risk. Narrow it if the target is Internet-facing.
- `nextcloud.<domain>` proxies to `http://192.168.0.4:8080`, a different LAN
  host. Pass `--nextcloud-upstream http://<host>:<port>` to change it.
- The Let's Encrypt certificate only covers `noadminabusearda.opik.net` and
  `cockpit.noadminabusearda.opik.net`. If you change `--domain`, the bundle
  skips the old certificate and you must issue a new one with `--certbot` or
  manually.
- Ports 80/443 must be reachable from the Internet for HTTP-01 renewal, and DNS
  must point at the target.
- Docker and firewalld both manage nftables/iptables rules. The `docker` zone
  and `docker-forwarding` policy are reproduced. If container networking
  misbehaves on a newer firewalld, check `firewall-cmd --get-active-zones` and
  `nft list ruleset`.

## Software-specific

- **Docker image tags drift.** `mysql:8` may resolve to MySQL 8.4, and
  `guacamole/guacamole:latest` may be newer than the source's schema. The
  included `initdb.sql` is the source's schema (Guacamole 1.x). If the
  Guacamole container refuses to start, either pin the image tags to the
  versions that match the schema or download the matching
  `initdb.sql` from the Guacamole release you deploy.
- **Guacamole data is not copied.** Users, connections, sharing profiles and
  history live in MySQL. The replica creates the default `guacadmin` /
  `guacadmin` account from `initdb.sql`; change the password immediately.
- **Minecraft duplicate mods.** The source has multiple versions of
  `fabric-api`, `ferritecore`, `iris`, `modmenu` and `sodium` active at once.
  Fabric Loader may refuse to start with duplicate mod IDs. Use
  `scripts/dedupe-minecraft-mods.sh` to move older versions aside.
- **Minecraft first start downloads** the vanilla server, Fabric Loader and
  remapped mods. It needs Internet access and several hundred MB of disk.
  `server.jar` is a 179 KB Fabric installer, not a complete server.
- **Minecraft `-Xloggc`** is a legacy flag. If the target JVM rejects it,
  change `ExecStart` to `-Xlog:gc:log.txt`.
- **The source `minecraft.service` is broken** (no `ExecStart`). The replica
  supplies a working unit. The original is in `reference/minecraft.service`.
- **CoolerControl** needs supported hardware sensors. On a VM or unsupported
  board the daemon may start but expose no devices. It is optional; skip it
  with `--skip-coolercontrol`.
- **`cockpit-file-sharing`** came from the 45Drives repo, which returns 404 for
  Fedora 43. The package is not installed by the replica. `/etc/samba/smb.conf`
  still has the `include = registry` line and works with plain Samba if you
  install `samba` later.
- **`httpd` is installed but unused** on the source. The replica does not
  install it.
- **libvirt** is enabled but has no VMs. The replica installs it only if you
  keep it in the package list; it is not enabled by default.
- **PCP** (`pmcd`, `pmie`, `pmlogger`) is enabled and writes to
  `/var/log/pcp`. It is included for fidelity; skip it if you do not want
  performance metrics.

## Fidelity vs. security

Deliberate divergences from the source:

1. The Guacamole compose file with hard-coded credentials is **not** published
   under `/var/www/files`. The source exposed it through `autoindex on`.
2. The real `server.properties` (with `management-server-secret`) is only in
   `secrets/`; the applied template uses `CHANGE_ME`.
3. `/etc/shadow`, SSH host keys and Wi-Fi PSKs are not in the `etc/` overlay.
4. The replica does not copy `/home/andrey` or any user data.
5. The broken `minecraft.service` is replaced with a working unit.
6. `apply.sh` backs up every replaced file to
   `/var/backups/fedora-replica-<timestamp>`.

## Known source quirks preserved in the bundle

- `homelab.conf` has `proxy_set_header Upgrade $http_update;` (should be
  `$http_upgrade`). Normal HTTP works; WebSocket upgrades may not.
- `mods/enable-disable.sh` is missing spaces around `[` and does not work.
- `minecraft.service` has no `ExecStart`.
- `nextcloud.conf` has no certificate for its own hostname.
- The 45Drives repo is broken.
- The source has two identical CoolerControl repo files
  (`_copr:...` and `codifryed-CoolerControl-fedora-43.repo`). They define the
  same repo ID, so the replica installs only `_copr:...`.

These are documented rather than silently "fixed" so the replica stays
recognizable. Fix them deliberately if you want a cleaner target.
