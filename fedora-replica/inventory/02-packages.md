# 02 - Repositories and packages

The source has **2,502 installed packages** and **464 user-installed packages**.
Most of them are the GNOME Workstation desktop. `apply.sh` installs only the
service-relevant set; the full list is preserved for reference.

- Full installed list: `../raw/packages.txt`
- Full user-installed list: `packages-userinstalled.txt`
- Service-relevant subset: `packages-relevant.txt`

## Enabled repositories on the source

| Repository | Use in replica |
| --- | --- |
| `fedora` | Base packages |
| `updates` | Updates |
| `fedora-cisco-openh264` | Not needed on a server; left enabled if present |
| `rpmfusion-nonfree-nvidia-driver` | Desktop GPU only; **not applied** |
| `rpmfusion-nonfree-steam` | Desktop only; **not applied** |
| `google-chrome` | Desktop only; **not applied** |
| `copr:copr.fedorainfracloud.org:codifryed:CoolerControl` | Required for `coolercontrol` |
| `copr:copr.fedorainfracloud.org:phracek:PyCharm` | Desktop IDE; **not applied** |
| `45drives_enterprise` | Broken on Fedora 43 (`404` for `el43`); **not applied** |

The 45Drives repo is the source of `cockpit-file-sharing-4.5.5-1.el9`. Because
the repo returns 404 for Fedora 43, `apply.sh` does not install that package.
The Cockpit file-sharing configuration (`/etc/samba/smb.conf` with
`include = registry`) is still included, but the feature is optional.

## Curated package set applied by `apply.sh`

Core:

```text
nginx
certbot
python3-certbot-nginx
firewalld
chrony
rsyslog
tuned
irqbalance
thermald
mcelog
lm_sensors
smartmontools
policycoreutils-python-utils
setools-console
```

Cockpit:

```text
cockpit
cockpit-files
cockpit-networkmanager
cockpit-packagekit
cockpit-storaged
cockpit-system
cockpit-machines
cockpit-session-recording
```

Containers:

```text
moby-engine
docker-cli
docker-compose
docker-buildx
docker-compose-switch
containerd
```

Minecraft:

```text
java-25-openjdk-headless
```

Monitoring / optional:

```text
pcp
python3-pcp
nfs-utils
samba-client
qemu-guest-agent
libvirt-daemon-kvm
virt-install
```

Utilities:

```text
curl
git
jq
unzip
tar
tmux
screen
htop
vim-enhanced
wget2-wget
dnf5-plugins
dnf5-plugin-automatic
```

`coolercontrol` comes from the CoolerControl COPR and is installed separately.
`httpd`, PHP, MariaDB/MySQL client libraries, and the desktop packages present
on the source are **not** installed: they are either unused or belong to the
GNOME desktop.

## Version drift warning

The source is Fedora 43, whose support ends **2026-12-02**. A new Fedora
Server install will almost certainly be Fedora 44 or newer. Package names in
the list above are stable, but versions and some defaults will differ. The
inventory records the exact source versions in `packages-relevant.txt`; do not
pin them unless you deliberately want an older release.

The source has duplicate installed versions of a few packages (for example two
`nginx-core`, two `moby-engine`, two `docker-cli`). That is an artifact of
updates and is not reproduced; `dnf` installs the current version.

## RPM-owned `/etc` files that differ from their packages

`rpm -Va` reported only these content changes:

```text
/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:phracek:PyCharm.repo
/etc/yum.repos.d/google-chrome.repo
/etc/yum.repos.d/rpmfusion-nonfree-nvidia-driver.repo
/etc/yum.repos.d/rpmfusion-nonfree-steam.repo
/etc/sysconfig/livesys
/etc/sysconfig/lm_sensors
/etc/default/grub
/etc/tlog/tlog-rec-session.conf
/etc/samba/smb.conf
/etc/vimrc
```

Only `lm_sensors`, `tlog-rec-session.conf`, `smb.conf` and the repo files are
in the overlay. `livesys` and `vimrc` differ only in packaging/metadata
noise; `grub` is hardware-specific and kept as a reference.

There are **133 unowned files** under `/etc`; the full list is in
`etc-unowned.txt`. The curated overlay in `../etc/` contains the meaningful
ones.
