FROM alpine:latest

RUN apk add --no-cache bash postgresql-client

WORKDIR /home/postgres
COPY --from=postgrest/postgrest /bin/postgrest /bin
COPY . .

RUN chown -R postgres:postgres /home/postgres
USER postgres

CMD exec ./run.sh
