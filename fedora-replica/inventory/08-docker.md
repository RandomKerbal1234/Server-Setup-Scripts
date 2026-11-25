# 08 - Docker and Guacamole

## Engine

- Packages: `moby-engine`, `docker-cli`, `containerd`, `docker-compose`,
  `docker-buildx`, `docker-compose-switch`
- `docker.service` and `docker.socket` enabled and active
- No `/etc/docker/daemon.json`
- Default bridge networks and address pools
- Docker group: `docker` (GID 967), member `andrey`

The source uses Fedora's `moby-engine` packages, not Docker Inc.'s
`docker-ce` repository. `apply.sh` installs the Fedora packages for the same
reason.

## Compose project

Project name: `guac-mysql`
Working directory: `/home/andrey/guac-mysql`
Compose file: `/home/andrey/guac-mysql/docker-compose.yml`
Database schema: `/home/andrey/guac-mysql/initdb.sql`

```yaml
services:
  guac-mysql:
    image: mysql:8
    container_name: guac-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: <secret>
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacuser
      MYSQL_PASSWORD: <secret>
    volumes:
      - mysql_data:/var/lib/mysql
    networks:
      - guacnet
  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: unless-stopped
    networks:
      - guacnet
  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      GUACD_HOSTNAME: guacd
      MYSQL_HOSTNAME: guac-mysql
      MYSQL_DATABASE: guacamole_db
      MYSQL_USER: guacuser
      MYSQL_PASSWORD: <secret>
    depends_on:
      - guacd
      - guac-mysql
    networks:
      - guacnet

volumes:
  mysql_data:

networks:
  guacnet:
```

The real file with credentials is
`../secrets/docker/guac-mysql/docker-compose.yml`. A redacted reference is in
`../docker/guac-mysql/docker-compose.yml`.

## Containers on the source

| Container | Image | Ports | Notes |
| --- | --- | --- | --- |
| `guacamole` | `guacamole/guacamole:latest` | `0.0.0.0:8080->8080/tcp` | web UI, 1.12 GB image |
| `guac-mysql` | `mysql:8` | `3306`, `33060` internal | 1.12 GB image |
| `guacd` | `guacamole/guacd:latest` | `4822` internal | healthy, 380 MB image |

All three use `restart: unless-stopped` and are on the `guacnet` network.
`guac-mysql` is also on the compose default network `guac-mysql_default`; the
source has both networks because the project was recreated.

Volumes:

- `guac-mysql_mysql_data` - MySQL data, **excluded**
- an anonymous volume `89c17bf...` - not used by the compose file

Networks:

- `guac-mysql_default`
- `guac-mysql_guacnet`
- `guacnet`
- default `bridge`, `host`, `none`

The replica recreates the compose project and networks; the old network IDs
and stale bridge interfaces are not reproduced.

## Database initialization

`initdb.sql` contains **schema only**, not the source data. It creates the
Guacamole tables and the default administrator:

- user: `guacadmin`
- password: `guacadmin`

The source database almost certainly had its admin password changed and
contained connection definitions, users and history. Those are data and are
**not** copied. After the replica is running, log in at
`https://<domain>/guac/` and change the `guacadmin` password immediately.

`apply.sh` imports `initdb.sql` only if the `guacamole_db` schema has no
tables. It waits for MySQL, checks `information_schema.tables`, imports, then
restarts the `guacamole` container.

Manual equivalent:

```bash
cd /home/andrey/guac-mysql
docker compose up -d
# wait for mysql
docker exec -i guac-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" guacamole_db < initdb.sql
docker compose restart guacamole
```

## Secrets

The source compose file hard-codes:

- MySQL root password (the same string as the system password)
- Guacamole database user password (the source value is in the secret compose file)

Both are in the secret compose file. If you do not use `--with-secrets`,
`apply.sh` generates random passwords and writes a `.env` file instead. If
you restore an old `guacamole_db` dump later, use the credentials that match
that dump.

## Excluded Docker data

- `/var/lib/docker` (images, containers, volumes, overlayfs)
- the `mysql_data` volume
- container logs
- Guacamole connection/user data in MySQL

The stack is rebuilt from images and `initdb.sql`; user connections must be
recreated or restored from a separate database dump.
