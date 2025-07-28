CREATE ROLE web_anon nologin;
CREATE ROLE authenticator LOGIN;
CREATE ROLE koios;
DROP EXTENSION IF EXISTS pg_cardano;
CREATE EXTENSION pg_cardano;
