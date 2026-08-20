# This container is a Postgres *client*, not a server. It runs psql against RDS
# and exits. Basing it on postgres:17-alpine shipped an unused server binary,
# initdb, replication tooling, and gosu -- whose embedded Go stdlib generated a
# recurring stream of CVE findings. alpine + postgresql17-client matches the
# same Alpine 3.24 / psql 17 versions with none of that surface.
FROM alpine:3.24

RUN apk add --no-cache postgresql17-client

WORKDIR /db-init

COPY schema.sql bootstrap.sql seed.sql ./
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Non-root system account: no password, no home, no login shell. The SQL files
# stay root-owned and world-readable -- this container only reads them, so the
# app user having no write access to its own scripts is the tighter default.
# entrypoint.sh is committed mode 644, so the chmod is required, not cosmetic.
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
  && adduser -S -D -H -u 10001 app

USER app

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
