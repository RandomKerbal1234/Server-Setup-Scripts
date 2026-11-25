# 03 - Services and listening ports

Full `systemctl list-unit-files --state=enabled` output is in
`units-enabled.txt`. The source is a Workstation install, so the list contains
many desktop units that the replica does not need.

## Server-relevant units enabled on the source

| Unit | State | Replica action |
| --- | --- | --- |
| `sshd.service` | enabled, active | enable |
| `NetworkManager.service` | enabled, active | enable (default on Fedora) |
| `NetworkManager-wait-online.service` | enabled | enable |
| `firewalld.service` | enabled, active | enable |
| `nginx.service` | enabled, active | enable |
| `docker.service` / `docker.socket` | enabled, active | enable |
| `cockpit.socket` | enabled, active | enable |
| `chronyd.service` | enabled, active | enable |
| `rsyslog.service` | enabled, active | enable |
| `tuned.service` | enabled, active | enable |
| `irqbalance.service` | enabled, active | enable |
| `lm_sensors.service` | enabled, active | enable |
| `smartd.service` | enabled, active | enable |
| `thermald.service` | enabled, active | enable |
| `mcelog.service` | enabled, active | enable |
| `coolercontrold.service` | enabled, active | enable if installed |
| `pmcd.service`, `pmie.service`, `pmlogger.service` | enabled, active | enable |
| `libvirtd.service` | enabled, **inactive** | optional; no VMs on source |
| `qemu-guest-agent.service` | enabled, active | optional; only for VMs |
| `certbot-renew.timer` | enabled, active | enable |
| `dnf5-automatic.timer` | enabled, active | enable |
| `fstrim.timer` | enabled, active | enable |
| `logrotate.timer` | enabled, active | enable (package default) |
| `plocate-updatedb.timer` | enabled, active | optional |
| `unbound-anchor.timer` | enabled, active | optional; `unbound` is not a DNS server here |

## Desktop / hardware units intentionally not reproduced

`gdm.service`, `accounts-daemon.service`, `bluetooth.service`,
`switcheroo-control.service`, `udisks2.service`, `upower.service`,
`rtkit-daemon.service`, `uresourced.service`, `cups.path` / `cups.socket`,
`avahi-daemon.service`, `ModemManager.service`, `abrt-*`, `livesys*`,
`vboxservice.service`, `vgauthd.service`, `vmtoolsd.service`,
`rpm-ostree-countme.timer`, `iscsi-*`, `raid-check.timer`, `mdmonitor.service`.

The replica sets `multi-user.target` by default because it installs no desktop.
If the target really needs a graphical session, run
`systemctl set-default graphical.target` after installing one.

## Units that are installed but not active

- `httpd.service` - Apache is installed but nginx owns ports 80/443. Not
  installed by the replica.
- `smb.service` / `nmb.service` - Samba server is **not** installed; only
  `samba-client` and `samba-common` are present. `/etc/samba/smb.conf` exists
  and was touched by Cockpit file sharing, but no SMB service runs.
- `unbound.service` - only `unbound-anchor` timer is enabled; no resolver.
- `libvirtd.service` - enabled, but `virsh list --all` is empty and the
  default network is the only libvirt network. Safe to skip.
- `bluemap` / `dynmap` - both mod jars are disabled (`.jar.disabled`), so
  nothing listens on 8100 or 8123. nginx still has a `/bluemap/` proxy that
  will return 502 until the mod is enabled.

## The broken Minecraft unit

The source has `/etc/systemd/system/minecraft.service`, but it is only 57
bytes and has no `ExecStart`:

```ini
[Unit]
Description=Minecraft Server
After=network.target
```

The server was started manually as user `minecraft`:

```text
java -Xmx18g -Xms512M -Xloggc:log.txt -jar server.jar nogui
```

The replica replaces this with a working unit in
`../minecraft/systemd/minecraft.service`. The original is preserved as
`reference/minecraft.service`.

## Listening ports

See `ports.txt`. The important externally reachable ports are:

- `22/tcp` SSH
- `80/tcp`, `443/tcp` nginx
- `8080/tcp` Guacamole
- `9090/tcp` Cockpit
- `25565/tcp` Minecraft

The firewalld `FedoraWorkstation` zone also opens **all TCP and UDP ports
1025-65535**, which covers Minecraft, Guacamole, Cockpit and the PCP/cooler
ports if they were bound externally.
