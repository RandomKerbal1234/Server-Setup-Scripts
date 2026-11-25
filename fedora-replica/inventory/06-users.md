# 06 - Users and groups

## Human users

| User | UID | GID | GECOS | Home | Shell | Groups |
| --- | --- | --- | --- | --- | --- | --- |
| `andrey` | 1000 | 1000 | Andrey Krioukov | `/home/andrey` | `/bin/bash` | `wheel`, `docker` |
| `minecraft` | 1001 | 1001 | minecraft | `/home/minecraft` | `/bin/bash` | - |
| `mom` | 1002 | 1002 | Mom | `/home/mom` | `/bin/bash` | - |
| `ml` | 1003 | 1003 | (empty) | `/home/ml` | `/bin/bash` | - |

`root` is the only other login-capable account. All service accounts use
`/sbin/nologin` or `/usr/sbin/nologin`.

## Relevant groups

| Group | GID | Members |
| --- | --- | --- |
| `wheel` | 10 | `andrey` |
| `docker` | 967 | `andrey` |
| `kvm` | 36 | `qemu` |
| `libvirt` | 988 | (none) |
| `qemu` | 107 | (none) |
| `printadmin` | 995 | (none) |
| `pcp` | 966 | (none) |
| `nginx` | 968 | (none) |
| `tlog` | 965 | (none) |

`andrey` has passwordless-by-membership sudo through `%wheel` in
`/etc/sudoers`; no custom `sudoers.d` files exist.

## Passwords and authentication

- `/etc/shadow` and `/etc/gshadow` are **not** copied.
- SSH host keys are **not** copied; the target generates new ones.
- The known `andrey` password is stored in
  `../secrets/system/andrey-password.txt` for reference. `apply.sh` does not
  set it unless you pass `--set-passwords`.
- Passwords for `minecraft`, `mom` and `ml` were not recoverable and are not
  in the bundle. Set them on the target with `passwd <user>` if interactive
  login is needed. The Minecraft service only needs the account to exist and
  own `/home/minecraft/server`; it does not need a password.
- The source uses the stock Fedora `authselect` profile `local` with
  `with-silent-lastlog`, `with-mdns4`, `with-fingerprint`. No LDAP, Kerberos,
  or SSSD domain is configured.

## Subordinate UID/GID ranges

`/etc/subuid` and `/etc/subgid` contain the usual per-user ranges created by
`useradd` (for rootless containers/user namespaces). The replica does not copy
the files; `useradd` creates equivalent entries. If you need the exact ranges,
read them from the source before decommissioning.

## Home directories

| Path | Owner | Mode | Notes |
| --- | --- | --- | --- |
| `/home/andrey` | `andrey:andrey` | 700 | contains the Guacamole compose project |
| `/home/minecraft` | `minecraft:minecraft` | 700 | contains the server and a 5.17 GB tarball |
| `/home/mom` | `mom:mom` | 700 | user data, excluded |
| `/home/ml` | `ml:ml` | 700 | user data, excluded |

`/home/andrey/guac-mysql` contains `docker-compose.yml` and `initdb.sql`.
The compose file has credentials; it is reproduced from
`../secrets/docker/guac-mysql/`.

## Minecraft account details

- The server runs as `minecraft` (UID 1001).
- `/home/minecraft/server` is owned by `minecraft:minecraft`.
- `/home/minecraft/server/mods` contains files owned by `root` and
  `minecraft`; the replica normalizes ownership to `minecraft:minecraft`.
- `/usr/local/bin/ntwrkc` is owned by `minecraft` and is a Wi-Fi helper; not
  installed by default.

## Creating the users

`steps/30-users.sh` creates the accounts idempotently. It tries to use the
source UIDs (1000-1003) when free, and falls back to the next available UID
with a warning. It does not force UIDs if they are already taken; file
ownership is applied by name, so the numeric UID does not matter for the
replica to work.
