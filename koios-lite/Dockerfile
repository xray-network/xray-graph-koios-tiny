FROM alpine:latest

RUN apk add --no-cache bash postgresql-client

ARG \
  WORKDIR=/home/postgres

ENV \
  WORKDIR=$WORKDIR \
  PGPASSFILE=$WORKDIR/.pgpass

WORKDIR $WORKDIR

COPY --from=postgrest/postgrest /bin/postgrest /bin
COPY . .
RUN chown -R postgres:postgres $WORKDIR

USER postgres
EXPOSE 8050

CMD exec ./koios-lite-entrypoint.sh

