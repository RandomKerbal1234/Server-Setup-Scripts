# Inventory index

This directory is the human-readable record of the source server. It is split by
subsystem so it can be read or diffed without loading one giant report.

| File | Contents |
| --- | --- |
| `01-system.md` | OS, kernel, hardware, hostname, timezone, locale, tuned, SELinux |
| `02-packages.md` | Repository setup and the curated package set used by `apply.sh` |
| `03-services.md` | Enabled services, listening ports, service-by-service notes |
| `04-network.md` | Interfaces, addressing, NetworkManager profiles, DNS |
| `05-storage.md` | Disks, btrfs subvolumes, fstab, zram, trim |
| `06-users.md` | Users, groups, UIDs, memberships, password handling |
| `07-web.md` | nginx sites, TLS, Cockpit, certbot, `/var/www/files` |
| `08-docker.md` | Docker engine and the Guacamole stack |
| `09-minecraft.md` | Fabric server, mods, configs, systemd, exclusions |
| `10-exclusions.md` | Data that was deliberately not copied |
| `11-differences.md` | Hardware-specific and version-specific caveats |

Raw collected output is in `../raw/`. The files that are safe to publish are
also copied into this directory:

- `packages-userinstalled.txt` - full `dnf repoquery --userinstalled` output
- `packages-relevant.txt` - service-relevant subset with versions
- `units-enabled.txt` - `systemctl list-unit-files --state=enabled`
- `ports.txt` - listening sockets extracted from `ss -tlnp`
- `etc-unowned.txt` - files under `/etc` not owned by any RPM
- `etc-modified.txt` - RPM-owned `/etc` files whose content differs from the RPM
- `reference/` - original copies of files that must not be applied blindly
  (`fstab`, `default/grub`, `minecraft.service`, `sshd_config`, etc.)

## Source identity

- Hostname: `fedora` (transient; static hostname was unset)
- Public name: `noadminabusearda.opik.net`
- LAN address: `192.168.0.3/24`
- Role: home lab host running nginx, Cockpit, Guacamole in Docker, and a
  Fabric Minecraft server
- Installed edition: Fedora Linux 43 Workstation
- Support end: **2026-12-02** (the source is one week from EOL)
