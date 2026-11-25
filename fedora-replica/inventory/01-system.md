# 01 - System identity

## Operating system

| Item | Value |
| --- | --- |
| Distribution | Fedora Linux 43 (Workstation Edition) |
| `ID` / `VERSION_ID` | `fedora` / `43` |
| Kernel | `7.3.3-100.fc43.x86_64` |
| Architecture | `x86_64` |
| Support end | `2026-12-02` |
| Default systemd target | `graphical.target` |
| Machine ID | `e251dbe0cb974a98b456a31c9bf0510f` (not copied) |

The source is a **Workstation** install, not Fedora Server. The replica bundle
only applies the server-relevant parts; GNOME, GDM, Bluetooth, printing and
desktop applications are intentionally not reproduced. See
`11-differences.md`.

## Hardware

| Item | Value |
| --- | --- |
| Vendor / model | Dell Inc. OptiPlex 9010 |
| Firmware | A13 (2013-03-27) |
| CPU | Intel Core i7-3770 @ 3.40 GHz |
| RAM | 24 GB class (18 GB Minecraft heap + system) |
| Boot | UEFI, GRUB 2 with BLS |
| Disk | single `sda` (see `05-storage.md`) |

## Hostname and network names

- Static hostname: **unset** on the source (`hostnamectl` shows only the
  transient name `fedora`).
- The replica defaults to `TARGET_HOSTNAME=fedora`.
- Public DNS name: `noadminabusearda.opik.net`.
- The TLS certificate also covers `cockpit.noadminabusearda.opik.net`.
- `apply.sh` accepts `--hostname` and `--domain`; the nginx and Cockpit
  templates are rendered with the chosen domain.

## Time and locale

| Item | Value |
| --- | --- |
| Timezone | `America/New_York` (EST/EDT) |
| NTP | `chronyd`, active, DHCP-provided servers plus Fedora pool |
| Locale | `LANG=en_US.UTF-8` |
| Console keymap | `us` |
| X11 layout | `us` (not applied on a headless target) |

`/etc/chrony.conf` is the stock Fedora file (`pool 2.fedora.pool.ntp.org
iburst`, `sourcedir /run/chrony-dhcp`, `rtcsync`). No custom NTP servers.

## Kernel command line

Source `/etc/default/grub`:

```text
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
```

This is effectively stock. The source boot entry also has
`rootflags=subvol=root` (btrfs) and the tuned kernel parameters. Do **not**
copy the source GRUB entry verbatim to different hardware; see
`reference/default-grub` and `05-storage.md`.

## tuned

- Active profile: `throughput-performance`
- `tuned.service` and `tuned-ppd.service` enabled
- No custom tuned profile was found; the profile comes from the package.

## SELinux

- SELinux is enforcing (standard Fedora).
- Custom persistent booleans:
  - `httpd_can_network_connect` = on
  - `selinuxuser_execmod` = on
  - `virt_sandbox_use_all_caps` = on
  - `virt_use_nfs` = on
- No custom `semanage fcontext`, port, module, login, or user mappings were
  found.

`httpd_can_network_connect` is required for nginx proxying to Cockpit,
Guacamole, BlueMap and Nextcloud.

## Kernel modules

No custom module loading. `/etc/modprobe.d` contains the stock Fedora
blacklists plus `kvm.conf`, `lockd.conf`, `nfs.conf`-related entries and
`vhost.conf` from packages. Not part of the overlay.

## systemd resource-control drop-ins

`/etc/systemd/system.control/` contains transient CPU/IO/memory weights for
user slices and `user@*.service`. These were created at runtime (for example
by Cockpit or `systemd-run`) and are **not** reproduced. They are safe to
ignore.
