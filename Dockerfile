# One-shot schema-migration runner. Not a database — a slim image with psql
# and bash that applies the migrations to a target Postgres over the Unix
# socket, then exits. There is no long-running container.
#
# Base image is fully qualified (docker.io/library/...) so podman does not
# prompt for a registry during the build.
FROM docker.io/library/debian:bookworm-slim
WORKDIR /app

# postgresql-client provides psql (used by migrate.sh); bash for the runner's
# arrays and process substitution. No server, no TLS certs — socket only.
RUN apt-get update \
    && apt-get install -y --no-install-recommends bash postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Migrations + runner, baked in. migrate.sh defaults to /sql/migrations.
COPY src/migrations/ /sql/migrations/

CMD ["bash", "/sql/migrations/migrate.sh"]
