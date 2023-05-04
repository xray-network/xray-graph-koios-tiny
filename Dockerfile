FROM alpine:latest as koios-lite

RUN apk add --no-cache bash nano postgresql-client

ENV \
  WORKDIR=/home/postgres \
  PGPASSFILE=/home/postgres/.pgpass

WORKDIR /home/postgres

COPY --from=postgrest/postgrest /bin/postgrest /bin
COPY koios-lite .
COPY cardano-configurations cardano-configurations
COPY guild-operators guild-operators
COPY koios-artifacts koios-artifacts

RUN chown -R postgres:postgres /home/postgres

USER postgres
EXPOSE 8050

STOPSIGNAL SIGINT
ENTRYPOINT ["./entry-koios-lite.sh"]

