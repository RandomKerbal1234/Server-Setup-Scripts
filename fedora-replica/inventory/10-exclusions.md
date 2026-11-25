# 10 - What was deliberately not copied

The goal is a **configuration replica**, not a data migration. Everything below
was excluded on purpose. If you need any of it, copy it separately and treat it
as sensitive.

## System data

| Path | Approx. size | Reason |
| --- | --- | --- |
| `/var/lib/docker` | several GB | images, containers, overlayfs, container logs |
| Docker volume `guac-mysql_mysql_data` | - | MySQL data directory; Guacamole users/connections/history |
| `/var/log` | - | logs |
| `/var/cache`, `/var/tmp`, `/tmp` | - | caches and temporary files |
| `/var/lib/systemd/random-seed`, `/var/lib/systemd/credential.secret` | - | host-specific random state |
| `/var/lib/coolercontrol/plugins` | - | runtime plugin data |
| `/var/spool/mail`, `/var/mail` | - | mailboxes |
| `/var/www/files/server.tar.gz` | 5.17 GB | full Minecraft backup |
| `/home/minecraft/server.tar.gz` | 5.17 GB | full Minecraft backup |
| `/var/www/files/docker/guac-mysql/docker-compose.yml` | 881 B | contains credentials; redacted copy used instead |
| `/home/andrey/guac-mysql` | - | compose project; reproduced from the bundle, not copied |
| `/home/andrey` | - | user files |
| `/home/mom`, `/home/ml` | - | user files |
| `/home/minecraft/eaglertech`, `share`, `temp1`, `temp2` | - | user/runtime files |
| `/root` | - | root's files and shell history |

## `/etc` data that is not in the overlay

The `/etc` overlay is curated. The source has **1,993 files** under `/etc`; the
overlay contains only modified or unowned files that matter for the services.
Not copied:

- `/etc/shadow`, `/etc/gshadow`, `/etc/passwd-`, `/etc/group-`, `/etc/shadow-`,
  `/etc/gshadow-`, `/etc/subuid-`, `/etc/subgid-` - account databases; the
  replica creates accounts with `useradd`.
- `/etc/ssh/ssh_host_*` - SSH host keys; the target generates new ones.
- `/etc/cockpit/ws-certs.d/*` - Cockpit self-signed certificate; regenerated.
- `/etc/pki/*` - package-managed CA bundles and default keys.
- `/etc/credstore`, `/etc/credstore.encrypted` - systemd credentials.
- `/etc/lvm/*`, `/etc/libvirt/*`, `/etc/audit/*`, `/etc/polkit-1/*`,
  `/etc/firewalld/ipsets`, `/etc/firewalld/services` - package defaults or
  empty runtime state.
- `/etc/systemd/system.control/*` - transient CPU/IO/memory weights created at
  runtime; not configuration.
- `/etc/NetworkManager/system-connections/*` - contains Wi-Fi PSKs; moved to
  `../secrets/NetworkManager/`.
- `/etc/letsencrypt/*` - contains TLS private keys and the ACME account key;
  moved to `../secrets/letsencrypt/`.
- `/etc/coolercontrol/.passwd`, `coolercontrol.key` - moved to
  `../secrets/coolercontrol/`.
- `/etc/nvme/hostid`, `/etc/nvme/hostnqn` - host-specific NVMe identity.
- `/etc/machine-id`, `/etc/hostname` - host identity.
- `/etc/fstab`, `/etc/default/grub`, `/etc/kernel/cmdline` - disk/partition
  specific; kept only as `reference/`.
- `/etc/sysconfig/network`, `/etc/sysconfig/anaconda`, `/etc/sysconfig/kernel`,
  `/etc/sysconfig/bootloader` - installer artifacts.
- `/etc/dconf/*`, `/etc/alsa/*`, `/etc/cups/*`, `/etc/foomatic/*` - desktop,
  audio and printing state.
- `/etc/selinux/.config_backup` - installer artifact.
- `/etc/.pwd.lock`, `/etc/.updated` - runtime state.
- `/etc/grub.d/00_tuned` - package-provided helper, unchanged.
- `/etc/vimrc`, `/etc/sysconfig/livesys` - RPM verify noise; not meaningful.
- `/etc/systemd/system/httpd.service.d`, `nginx.service.d` - empty on the
  source.

## Minecraft data

| Path | Approx. size | Reason |
| --- | --- | --- |
| `world/region`, `world/entities`, `world/poi` | GB | terrain and entities |
| `world/level.dat`, `world/level.dat_old` | - | world metadata |
| `world/playerdata`, `world/advancements`, `world/stats` | - | player data |
| `world/data`, `world/datapacks` (if present) | - | world data |
| `world/ledger.sqlite` | ~165 MB | Ledger block-change database |
| `world/serverconfig/` | - | **included** (4 TOML files + readme) |
| `logs/`, `log.txt`, `debug/`, `crash-reports/` | - | logs |
| `cache/`, `.fabric/`, `libraries/`, `versions/` | - | downloaded/processed jars |
| `usercache.json`, `usernamecache.json` | - | player cache |
| `bluemap/`, `bluemap/web/` | - | rendered map data |
| `dynmap/web/`, `renderdata/`, `templates/`, `texturepacks/`, `export/`, `import/`, `world.pending`, `ids-by-ip.txt` | - | rendered map data and runtime state |
| `dynmap/colorschemes/` | ~30 MB | optional color maps; Dynmap is disabled |
| `unusedmods/` | - | duplicate Dynmap jar |
| `mods/*.jar.disabled` | - | **included** for fidelity |
| `config/GrimAC/violations.sqlite` | - | violation data |
| `config/spark/tmp/`, `config/spark/activity.json` | - | profiler data |
| `/home/minecraft/.msmtprc`, `.muttrc` | - | moved to `../secrets/minecraft/mail/` |
| `/home/minecraft/.msmtp.log`, `.bash_history`, `.viminfo`, `.lesshst`, `.ssh`, `.cache`, `.local`, `.mozilla` | - | user data |

## Why these exclusions matter

- **Privacy**: player names, IPs, chat, advancements and stats are personal
  data. The replica creates a fresh world with no players.
- **Size**: the two 5.17 GB tarballs alone dwarf the rest of the bundle.
- **Correctness**: Docker volumes, caches and rendered maps are tied to the old
  host and would be stale or inconsistent on a new one.
- **Security**: `/etc/shadow`, SSH host keys, Wi-Fi PSKs and TLS private keys
  are only in `../secrets/`, which is mode `700` and is installed only with
  `--with-secrets`.
