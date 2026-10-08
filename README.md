# datomic-transactor

A Docker image that runs the [Datomic Pro](https://docs.datomic.com/) transactor with
PostgreSQL storage. The transactor only reads a properties file, so the entrypoint renders
`transactor.properties` from environment variables and starts it.

## Quick start (local)

```bash
docker compose up -d --build           # Postgres (in memory), init-db, transactor
docker compose run --rm smoke-test     # creates a schema, inserts and queries data
docker compose down
```

Postgres runs on `tmpfs`, so nothing persists between runs.

## Configuration

All configuration is by environment variable.

| Variable | Default | Purpose |
|---|---|---|
| `DATOMIC_DB_HOST` | required | Postgres host |
| `DATOMIC_DB_PORT` | `5432` | Postgres port |
| `DATOMIC_DB_NAME` | `datomic` | Postgres database |
| `DATOMIC_DB_USER` | required | Postgres user the transactor connects as |
| `DATOMIC_DB_PASSWORD` | required | Password for that user |
| `DATOMIC_PORT` | `4334` | Port the transactor listens on |
| `DATOMIC_ALT_HOST` | container hostname | Address peers use to reach the transactor (see below) |
| `DATOMIC_LICENSE_KEY` | unset | Written to the properties file only if set |

Memory settings are in `transactor.properties.template`.

## Database setup: `init-db`

Datomic's `bin/sql` scripts create the database, the `datomic_kvs` table and the `datomic`
role. They need a Postgres superuser, so they run in a separate one-shot mode, and the
long-running transactor never holds admin credentials:

```bash
docker run --rm --network <net> \
  -e DATOMIC_DB_HOST=<postgres> \
  -e DATOMIC_ADMIN_USER=postgres -e DATOMIC_ADMIN_PASSWORD=<admin password> \
  -e DATOMIC_DB_PASSWORD=<password for the datomic role> \
  datomic-transactor init-db
```

The scripts are run unmodified, each guarded by an existence check, so `init-db` is safe to
re-run. They hardcode the database and role name `datomic`, so `DATOMIC_DB_NAME` must be
`datomic`. `postgres-user.sql` hardcodes the role's password as `datomic`; if
`DATOMIC_DB_PASSWORD` is set, `init-db` replaces it right after.

The transactor refuses to start if the `datomic_kvs` table doesn't exist.

## Connecting an application

A peer URI names Postgres only, not the transactor:

```
datomic:sql://<db-name>?jdbc:postgresql://<postgres-host>:5432/datomic?user=<user>&password=<password>
```

The peer reads data from Postgres, and also reads the transactor's address from it. That
address is `DATOMIC_ALT_HOST:DATOMIC_PORT`, written when the transactor starts. The peer
then connects to it directly. So an application needs network access to **both**:

1. Postgres, with credentials.
2. The transactor at `DATOMIC_ALT_HOST` on `DATOMIC_PORT`.

`DATOMIC_ALT_HOST` must be a name or address that every peer can resolve and reach. On a
shared Docker network that is the transactor's container name. For peers outside the
network, use the host's address and publish `DATOMIC_PORT`.

## Deploying (Postgres container on Unraid)

1. Run the stock `postgres` container with a superuser password.
2. Run the image once with `init-db` (above).
3. Run the image normally with `DATOMIC_DB_HOST`, `DATOMIC_DB_USER=datomic`,
   `DATOMIC_DB_PASSWORD` and `DATOMIC_ALT_HOST`.

Putting Postgres, the transactor and your apps on one user-defined Docker network and using
the transactor's container name for `DATOMIC_ALT_HOST` avoids any published ports.

## Smoke test

`test/` is a stand-in for an external application: its own image, built from plain
`clojure`, with the Datomic peer from Maven Central. `test/smoke_test.clj` is a `clojure.test` suite that creates a schema,
upserts three people, and queries them. It uses a fresh database and deletes it afterwards.

- `docker compose run --rm smoke-test` runs it inside the compose network.
- To run it from the host, `transactor` must resolve to `127.0.0.1` (for example via
  `/etc/hosts`), and `DATOMIC_URI` must point at `localhost:5432`. See `test/smoke_test.clj`.

## CI and releases

- **Forgejo** (`.forgejo/workflows/test.yml`) runs the smoke test on PRs and pushes to
  `main`. `main` is protected: changes go through a PR, and the
  `Smoke test / smoke (pull_request)` check must pass. Job containers have no docker
  socket, so the workflow installs Datomic and runs `entrypoint.sh` directly instead of
  using the compose stack. That means PR CI does not build or run the image itself.
- **GitHub** (`.github/workflows/publish.yml`) runs when a `v#.#.#` tag arrives via the
  Forgejo push mirror. It builds the image, runs the compose stack and smoke test against
  that exact image, and only then pushes `vadercows/datomic-transactor` to Docker Hub. This
  is where the real image is first tested. It needs the `DOCKERHUB_USERNAME` and
  `DOCKERHUB_TOKEN` secrets on the GitHub repo.

To release, tag on the forge: `git tag v1.2.3 && git push origin v1.2.3`.
