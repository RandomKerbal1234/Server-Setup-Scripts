# 05 - Storage

## Layout

Single disk `sda` (virtual/physical, 64 GB class), GPT:

| Partition | FS | Size | Mount | Notes |
| --- | --- | --- | --- | --- |
| `sda1` | EFI System | ~600 MB | `/boot/efi` | not shown in the source `df` output |
| `sda2` | ext4 | 2.0 GB | `/boot` | UUID `f3f0645c-ef4d-4442-b8a4-608837359182` |
| `sda3` | btrfs | 58 GB | `/`, `/home` | UUID `ccf7a767-b3de-40e9-b953-3d0a49ac5880` |
| `zram0` | swap | ~12 GB | `[SWAP]` | zram-generator default |

btrfs subvolumes:

- `subvol=root` -> `/`
- `subvol=home` -> `/home`
- mount option `compress=zstd:1` on both
- `ssd`, `discard=async`, `space_cache=v2`

`df` shows `/` and `/home` at 58 GB (same filesystem), `/boot` at 2 GB.

## `/etc/fstab` on the source

```fstab
UUID=ccf7a767-b3de-40e9-b953-3d0a49ac5880 /     btrfs subvol=root,compress=zstd:1 0 0
UUID=f3f0645c-ef4d-4442-b8a4-608837359182 /boot ext4  defaults                          1 2
UUID=ccf7a767-b3de-40e9-b953-3d0a49ac5880 /home btrfs subvol=home,compress=zstd:1 0 0
```

No swap partition; zram provides swap. No NFS/CIFS mounts. No LVM, RAID or
encryption. `mdadm` is installed but no arrays exist.

The original file is in `reference/fstab`. **Do not copy it to the target**:
the UUIDs and partition layout are specific to the source disk. `apply.sh`
does not rewrite `/etc/fstab`; it only enables `fstrim.timer`.

## How to reproduce the layout

On a fresh Fedora install, choose btrfs with the default `root` and `home`
subvolumes and `compress=zstd:1`. If the target uses a different disk, keep
its own UUIDs and only add the mount options:

```fstab
UUID=<target-root>  /     btrfs subvol=root,compress=zstd:1 0 0
UUID=<target-boot>  /boot ext4  defaults                    1 2
UUID=<target-root>  /home btrfs subvol=home,compress=zstd:1 0 0
```

Then:

```bash
systemctl daemon-reload
mount -o remount /        # or reboot
systemctl enable --now fstrim.timer
```

## zram

Fedora's `zram-generator` creates `zram0` automatically. No custom
`/etc/systemd/zram-generator.conf` was found. The replica leaves the default
in place.

## Tuned / I/O

`tuned` is active with `throughput-performance`, which sets
`vm.swappiness=10` and other I/O tuning. `apply.sh` selects that profile.

## Docker and container storage

Docker data lives in `/var/lib/docker` and is **not** copied. The Guacamole
MySQL volume `guac-mysql_mysql_data` is data and is excluded. Recreating the
stack creates a fresh volume.

## Minecraft data

`/home/minecraft/server` contains the world, logs, caches, `.fabric` downloads
and a 5.17 GB `server.tar.gz`. All of that is excluded; only the server jar,
mods, configs and small JSON/text files are copied. See `09-minecraft.md`.

## Space estimates

| Item | Size |
| --- | --- |
| Curated `/etc` overlay | < 1 MB |
| Let's Encrypt secrets | ~136 KB |
| Minecraft mods + configs + jar | ~98 MB |
| Docker images (pulled on target) | ~2.6 GB |
| Fresh Minecraft world + Fabric downloads | several hundred MB to GB |

Allow at least 20 GB free for the full stack.
