#############################################################################################
### POSTGRES WITH PG_BECH32 ###

FROM postgres:17.2-bookworm as postgres

# Install PG_BECH32 extension
COPY koios-tiny/pg_bech32_install.sh /root/
RUN chmod +x /root/pg_bech32_install.sh
RUN ./root/pg_bech32_install.sh


#############################################################################################
### CARDANO-DB-SYNC ###

FROM ghcr.io/intersectmbo/cardano-db-sync:13.6.0.4 as cardano-db-sync-original

# Second stage: Start from a minimal Debian or Alpine base
FROM debian:bullseye-slim as cardano-db-sync

# Copy everything from the distroless image
COPY --from=cardano-db-sync-original / /

# Install necessary packages for adding repositories
RUN apt-get update && apt-get install -y wget gnupg

# Add PostgreSQL's official repo
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ bullseye-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Import the repository signing key
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Update apt and install PostgreSQL Client v16
RUN apt-get update && apt-get install -y postgresql-client-17

STOPSIGNAL SIGINT

ENTRYPOINT ["/bin/entrypoint"]


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

COPY koios-tiny/koios-artifacts/files/grest/rpc rpc
COPY koios-tiny/extra-rpc rpc/extra-rpc

COPY koios-tiny/koios-artifacts/files/grest/cron/jobs cron
COPY koios-tiny/extra-cron-jobs cron
COPY koios-tiny/cron-schedule /var/spool/cron/crontabs/postgres

# Adding permissions and setting the cron to run as the "postgres" user
RUN chmod +x cron/*
RUN chown -R postgres:postgres /home/postgres
RUN chown -R postgres:postgres /etc/crontabs
RUN mkdir -p /var/run && \
    chown postgres:postgres /var/run && \
    touch /var/run/crond.pid && \ 
    chown postgres:postgres /var/run/crond.pid && \
    chown postgres:postgres /usr/sbin/crond && \
    setcap cap_setgid=ep /usr/sbin/crond

# Switching user 
USER postgres

# Setting up an exposed port and starting a container
EXPOSE 8050/tcp
ENTRYPOINT ["./entrypoint.sh"]


#############################################################################################
### OGMIOS-TINY ###

FROM node:20 as ogmios-tiny

WORKDIR /usr/src/app

COPY ogmios-tiny .
RUN yarn install

EXPOSE 8700/tcp
CMD [ "node", "index.js" ]
