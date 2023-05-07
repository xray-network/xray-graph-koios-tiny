 FROM alpine:latest as koios-lite

# Installing packages...
RUN apk add --no-cache dcron libcap bash nano jq git postgresql-client

# Setting PGPASSFILE global ENV
ENV \
  HOME=/home/postgres \
  PGPASSFILE=/home/postgres/.pgpass

# Copying config & Koios files
WORKDIR /home/postgres
COPY --from=postgrest/postgrest /bin/postgrest /bin
COPY koios-lite/postgrest.conf .
COPY koios-lite/entry-koios-lite.sh .
COPY cardano-configurations cardano-configurations
COPY guild-operators/scripts/grest-helper-scripts/db-scripts db-scripts

COPY koios-artifacts/files/grest/rpc rpc
COPY koios-lite/rpc-extra rpc

COPY koios-artifacts/files/grest/cron/jobs cron
COPY koios-lite/cron-jobs-extra cron
COPY koios-lite/cron-schedule /var/spool/cron/crontabs/postgres

# Adding permissions and setting the cron to run as the "postgres" user
RUN chmod +x cron/*
RUN chown -R postgres:postgres /home/postgres
RUN chown -R postgres:postgres /etc/crontabs && \ 
    chown postgres:postgres /usr/sbin/crond && \
    setcap cap_setgid=ep /usr/sbin/crond

# Switching user 
USER postgres

# Setting up an exposed port and starting a container
EXPOSE 8050/tcp
STOPSIGNAL SIGINT
ENTRYPOINT ["./entry-koios-lite.sh"]

