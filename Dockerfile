#############################################################################################
### KOIOS-TINY ###

FROM alpine:latest as koios-tiny

# Installing packages...
RUN apk add --no-cache dcron libcap bash nano jq git postgresql-client

# Setting PGPASSFILE global ENV
ENV \
  HOME=/home/postgres \
  PGPASSFILE=/home/postgres/.pgpass

# Copying config & files
WORKDIR /home/postgres
COPY --from=postgrest/postgrest /bin/postgrest /bin
COPY config/postgrest/postgrest.conf .
COPY koios-tiny/entrypoint.sh .
COPY config/cardano-configurations cardano-configurations
COPY koios-tiny/guild-operators/scripts/grest-helper-scripts/db-scripts db-scripts

COPY koios-tiny/koios-artifacts/files/grest/rpc rpc
COPY koios-tiny/extra-rpc rpc

COPY koios-tiny/koios-artifacts/files/grest/cron/jobs cron
COPY koios-tiny/extra-cron-jobs cron
COPY koios-tiny/cron-schedule /var/spool/cron/crontabs/postgres

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
ENTRYPOINT ["./entrypoint.sh"]

