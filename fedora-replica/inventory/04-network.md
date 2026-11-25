# 04 - Network

## Interfaces on the source

| Interface | State | Address |
| --- | --- | --- |
| `eno1` | UP | `192.168.0.3/24`, IPv6 SLAAC `2601:189:4101:b7f0:.../64` |
| `lo` | UP | `127.0.0.1/8`, `::1/128` |
| `docker0` | DOWN | `172.17.0.1/16` |
| `br-938a01267881` | UP | `172.20.0.1/16` (Guacamole `guacnet`) |
| `br-cdb36edfa113` | DOWN | `172.18.0.1/16` (old compose network) |
| `br-f56ebf149b04` | DOWN | `172.19.0.1/16` (old `guacnet`) |
| `veth*` | UP | container pairs |

Default route: `192.168.0.1` via DHCP on `eno1`, metric 100.

The source uses **DHCP**, not a static address. The LAN address
`192.168.0.3` is a DHCP reservation or lease. On the target, either configure
a matching reservation or set a static address; the replica does not force an
IP.

## DNS

`systemd-resolved` is enabled. `/etc/resolv.conf` is the stub symlink:

```text
nameserver 127.0.0.53
options edns0 trust-ad
search .
```

No custom DNS servers. `/etc/hosts` is stock Fedora (localhost entries only).

## NetworkManager profiles

| Profile | Type | Interface | Active |
| --- | --- | --- | --- |
| `Wired connection 1` | 802-3-ethernet | `eno1` | yes |
| `BESThome` | 802-11-wireless | `wlp2s0` | no |
| `wireless` | 802-11-wireless | `wlp2s0` | no |
| `docker0`, `br-*` | bridge | - | created by Docker/libvirt |

The two Wi-Fi profiles contain WPA pre-shared keys. They are **not** in the
`etc/` overlay. They are stored under `../secrets/NetworkManager/` and are
**not installed automatically**, because the target interface name is likely
different:

- `BESThome` - SSID `BESThome`, PSK in the secret file
- `wireless` - hidden SSID `wireless`, PSK in the secret file

The source Wi-Fi interface is `wlp2s0`; the target may use a different name.
Edit `interface-name` before activating these profiles. A wired server does
not need them.

## Custom script

`/usr/local/bin/ntwrkc` (owned by `minecraft`) is a two-line helper:

```bash
nmcli device wifi rescan ssid "$1"
nmcli device wifi connect "$1" hidden yes --ask
```

It is included as `../extras/usr-local/bin/ntwrkc` but not installed by
default.

## firewalld

Default zone: **FedoraWorkstation** (not the Fedora Server default).

`FedoraWorkstation` zone:

```text
services: dhcpv6-client http https samba-client ssh
ports:    1025-65535/udp 1025-65535/tcp
forward:  yes
```

`docker` zone:

```text
target: ACCEPT
interfaces: docker0, br-938a01267881, br-cdb36edfa113, br-f56ebf149b04
forward: yes
```

`docker-forwarding` policy:

```text
target: ACCEPT
ingress-zone: ANY
egress-zone: docker
```

The zone and policy XML files are in `../etc/firewalld/`. `apply.sh` installs
them and runs the equivalent of:

```bash
firewall-cmd --set-default-zone=FedoraWorkstation
firewall-cmd --permanent --zone=FedoraWorkstation --add-service=dhcpv6-client
firewall-cmd --permanent --zone=FedoraWorkstation --add-service=http
firewall-cmd --permanent --zone=FedoraWorkstation --add-service=https
firewall-cmd --permanent --zone=FedoraWorkstation --add-service=samba-client
firewall-cmd --permanent --zone=FedoraWorkstation --add-service=ssh
firewall-cmd --permanent --zone=FedoraWorkstation --add-port=1025-65535/tcp
firewall-cmd --permanent --zone=FedoraWorkstation --add-port=1025-65535/udp
firewall-cmd --reload
```

The wide `1025-65535` opening is deliberate in the source but is a security
trade-off. If the target is Internet-facing, narrow it to the ports actually
needed (22, 80, 443, 8080, 9090, 25565) and keep Docker's own rules in mind.

## Docker networking

Docker creates the bridge networks and inserts its own iptables/nftables
rules. The `docker` firewalld zone exists so that forwarded container traffic
is accepted. The `docker-forwarding` policy allows forwarding from any zone
into the Docker zone. Without these, container publishing may still work but
inter-container routing and return traffic can be blocked by firewalld.

Docker's default address pools are used (`172.17.0.0/16`, then
`172.18.0.0/16`, etc.). No `/etc/docker/daemon.json` exists on the source.
