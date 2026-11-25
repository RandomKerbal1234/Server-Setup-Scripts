# 09 - Minecraft server

## Summary

| Item | Value |
| --- | --- |
| Directory | `/home/minecraft/server` |
| Owner | `minecraft:minecraft` |
| Loader | Fabric Loader 0.18.4 |
| Minecraft | 1.21.11 |
| Java | OpenJDK 25.0.5 (`java-25-openjdk`) |
| Launcher | `server.jar` (Fabric installer 1.1.1, 179 KB) |
| Port | 25565 |
| Heap | `-Xmx18g -Xms512M` |
| Start command | `java -Xmx18g -Xms512M -Xloggc:log.txt -jar server.jar nogui` |
| systemd | broken `minecraft.service` on source; replica supplies a working one |

The server was started manually, not by systemd. The source
`/etc/systemd/system/minecraft.service` contains only:

```ini
[Unit]
Description=Minecraft Server
After=network.target
```

and has no `ExecStart`. The running process is the manual `java` command
above (PID 643969 at collection time).

## What is included

- `server.jar` - Fabric server launcher
- `start.sh` - original manual start script
- `eula.txt` - `eula=true`
- `server.properties` - redacted template (real one in `secrets/minecraft/`)
- `ops.json`, `whitelist.json`, `banned-players.json`, `banned-ips.json`
- `mods/` - all 39 files (29 active jars, 9 `.jar.disabled`, `enable-disable.sh`)
- `config/` - all mod configs except runtime data (see exclusions)
- `defaultconfigs/` - empty on the source
- `dynmap/` - top-level Dynmap config files (no render data, no colorschemes)
- `serverconfig/` - OpenPartiesAndClaims world configs, to be copied to
  `/home/minecraft/server/world/serverconfig/`

## What is excluded

| Path | Reason |
| --- | --- |
| `world/` | world data: region, entities, poi, playerdata, advancements, stats, `level.dat`, `ledger.sqlite` (165 MB) |
| `logs/`, `log.txt*` | logs |
| `cache/`, `.fabric/` | downloaded libraries, remapped jars, processed mods |
| `libraries/`, `versions/` | launcher data |
| `usercache.json`, `usernamecache.json` | player cache |
| `bluemap/web/`, `bluemap/` render data | rendered map data |
| `dynmap/web/`, `dynmap/renderdata/`, `dynmap/templates/`, `dynmap/texturepacks/`, `dynmap/export/`, `dynmap/import/` | rendered map data / assets |
| `dynmap/colorschemes/` | 30 MB of optional color maps (Dynmap is disabled) |
| `dynmap/world.pending`, `dynmap/ids-by-ip.txt` | runtime state |
| `config/GrimAC/violations.sqlite` | data |
| `config/spark/tmp/` | profiler temp files |
| `config/spark/activity.json` | runtime activity data |
| `unusedmods/` | duplicate Dynmap jar |
| `/home/minecraft/server.tar.gz` | 5.17 GB full backup |
| `.bash_history`, `.viminfo`, `.cache`, `.local`, `.mozilla`, `.ssh` | user data |
| `/home/minecraft/.msmtprc`, `.muttrc` | moved to `secrets/minecraft/mail/` |

## Mods

Active jars (29):

```text
Chunky-Fabric-1.4.55.jar
ForgeConfigAPIPort-v21.11.1-mc1.21.11-Fabric.jar
Jade-1.21.11-Fabric-21.1.1.jar
antixray.jar
appleskin-fabric-mc1.21.11-3.0.8.jar
c2me-fabric-mc1.21.11-0.3.6.0.0.jar
chunksfadein-fabric-3.0.20-1.21.11.jar
clientsort-fabric-2.1.6+1.21.11.jar
cloth-config-21.11.153-fabric.jar
fabric-api-0.140.0+1.21.11.jar
fabric-api-0.141.2+1.21.11.jar
ferritecore-8.0.3-fabric.jar
ferritecore-8.2.0-fabric.jar
grave.jar
iris-fabric-1.10.4+mc1.21.11.jar
iris-fabric-1.10.5+mc1.21.11.jar
jei-1.21.11-fabric-27.4.0.15.jar
kotlin.jar
ledger.jar
modmenu-17.0.0-alpha.1.jar
modmenu-17.0.0-beta.2.jar
placeholder-api-2.8.1+1.21.10.jar
plymer-core.jar
sodium-fabric-0.8.2+mc1.21.11.jar
sodium-fabric-0.8.3+mc1.21.11.jar
sodium-fabric-0.8.4+mc1.21.11.jar
sound-physics-remastered-fabric-1.21.11-1.5.1.jar
spark-profiler.jar
vanish-1.6.6+1.21.11.jar
```

Disabled jars (`.jar.disabled`):

```text
anticheat.jar.disabled
baritone-meteor-1.21.11.jar.disabled
bluemap.jar.disabled
dynmap.jar.disabled
flan.jar.disabled
meteor-client-1.21.11-48.jar.disabled
opac.jar.disabled
xminimap.jar.disabled
xworldmap.jar.disabled
```

### Duplicate mod IDs

The source has multiple versions of the same mod active at once:

- `fabric-api` 0.140.0 and 0.141.2
- `ferritecore` 8.0.3 and 8.2.0
- `iris` 1.10.4 and 1.10.5
- `modmenu` 17.0.0-alpha.1 and 17.0.0-beta.2
- `sodium` 0.8.2, 0.8.3 and 0.8.4

Fabric Loader normally refuses duplicate mod IDs. The source may be running
with only some of these jars loaded, or the server may have been started
before the newer jars were added. The bundle copies all of them faithfully.
If the target refuses to start with a duplicate-mod error, either remove the
older version of each pair or run:

```bash
./scripts/dedupe-minecraft-mods.sh --apply
```

which moves older versions to `mods/disabled-duplicates/`.

Several active mods are client-side only (`appleskin`, `iris`, `sodium`,
`modmenu`, `chunksfadein`, `clientsort`, `xaero` configs). They are harmless
on a server but waste memory; the source keeps them, so the replica does too.

### `mods/enable-disable.sh`

The original helper is syntactically broken:

```bash
if [$1 = "d"]
	mv $2 $2.disabled
elif [$1 = "e"]
	mv $2 ${2%%.disabled}
fi
```

It is included for fidelity but not used. The missing spaces around `[` make
it fail. The replica's `scripts/dedupe-minecraft-mods.sh` is a working
alternative for moving jars.

## `server.properties`

Key values:

```properties
server-port=25565
max-players=20
online-mode=true
white-list=false
enforce-whitelist=false
gamemode=survival
difficulty=normal
level-name=world
level-seed=
view-distance=32
simulation-distance=16
pause-when-empty-seconds=60
enable-rcon=false
enable-query=false
management-server-enabled=false
motd=DEFINATELY NOT stein's land
```

The source contains a `management-server-secret` even though the management
server is disabled. The template in `minecraft/server.properties` replaces it
with `CHANGE_ME`; the real value is in
`secrets/minecraft/server.properties`. If you enable the management server,
use a new secret.

## `ops.json`

```json
[
  {
    "uuid": "6ef5ac79-9969-450a-aa10-dd8aca61134f",
    "name": "RandomKerbal",
    "level": 4,
    "bypassesPlayerLimit": false
  }
]
```

`whitelist.json`, `banned-players.json` and `banned-ips.json` are empty.

## `world/serverconfig`

OpenPartiesAndClaims stores its per-world config under
`world/serverconfig/`:

- `openpartiesandclaims-default-player-config.toml`
- `openpartiesandclaims-expired-claim-config.toml`
- `openpartiesandclaims-server-claim-config.toml`
- `openpartiesandclaims-wilderness-config.toml`
- `readme.txt`

These are configuration, not world data, so they are included and copied to
`/home/minecraft/server/world/serverconfig/` before first start. If the
directory is missing, the mod regenerates defaults.

## Map mods

- **BlueMap** is disabled (`bluemap.jar.disabled`). Its config expects a
  webserver on `127.0.0.1:8100` with webroot `bluemap/web`; nginx proxies
  `/bluemap/` to that port. Enabling the jar requires accepting the Mojang
  EULA in `config/bluemap/core.conf` (`accept-download: true` is already set)
  and letting it render.
- **Dynmap** is disabled (`dynmap.jar.disabled`). Config uses filetree
  storage, `deftemplatesuffix: hires`, and webchat. Enabling it would listen
  on 8123 by default, but nginx does not proxy Dynmap.

## systemd unit used by the replica

`minecraft/systemd/minecraft.service`:

```ini
[Unit]
Description=Minecraft Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=minecraft
Group=minecraft
WorkingDirectory=/home/minecraft/server
ExecStart=/usr/bin/java -Xmx18g -Xms512M -Xloggc:log.txt -jar server.jar nogui
Restart=on-failure
RestartSec=10
SuccessExitStatus=0 1
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

The heap is rendered from `MINECRAFT_HEAP` (default `18G`). The target needs
more than 18 GB RAM for the default; use `--minecraft-heap 4G` on a smaller
host. The unit runs Java directly rather than through `start.sh` so systemd
can manage the process and send signals correctly.

## First start

`server.jar` is the Fabric installer, not a bundled vanilla server. On first
start it downloads:

- the vanilla Minecraft 1.21.11 server jar
- Fabric Loader 0.18.4
- remapped/processed mod jars

into `/home/minecraft/server/.fabric/` and `libraries/`. This needs Internet
access and several hundred MB of disk. The first start can take a few minutes.
Subsequent starts use the cached files.

`eula=true` is already set. The server creates `world/` on first start.

## Memory and Java

The source has 24 GB RAM and gives Minecraft 18 GB. Java 25 is installed with
`java-25-openjdk` (full JDK) and the `java` alternative points at
`/usr/lib/jvm/java-25-openjdk/bin/java`. The replica installs
`java-25-openjdk-headless`, which is sufficient for a server.

`-Xloggc:log.txt` is a legacy GC-log flag. It works on the source's Java 25
build but may print a deprecation warning. Keep it if you want byte-for-byte
behavior; replace with `-Xlog:gc:log.txt` if the JVM rejects it.

## Firewall

Port 25565 is covered by the `FedoraWorkstation` zone's
`1025-65535/tcp` opening. If you narrow the firewall, add `25565/tcp`
explicitly.
