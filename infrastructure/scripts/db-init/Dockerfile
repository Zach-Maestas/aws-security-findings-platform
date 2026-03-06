FROM postgres:16-alpine

WORKDIR /db-init

COPY schema.sql bootstrap.sql seed.sql ./
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
  && adduser -D -u 10001 app \
  && chown -R app:app /db-init

USER app

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
