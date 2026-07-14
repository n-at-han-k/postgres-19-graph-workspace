# Postgres 19 + SQL/PGQ graph-query playground

A one-command local lab for experimenting with **native property-graph queries**
in PostgreSQL 19 (SQL/PGQ, the SQL:2023 Part 16 standard), wired up so
[DBCode](https://dbcode.io) auto-connects and you can run graph queries from a
SQL Notebook.

> PostgreSQL 19 is in **beta** (`19beta1`, released 2026-06-04; final ~Sept 2026).
> The initial SQL/PGQ implementation supports **fixed-depth** pattern matching;
> variable-length paths land in a later release.

## 1. Start the database

```bash
docker compose up -d
docker compose logs -f          # wait for "database system is ready to accept connections"
```

The `init/` scripts run automatically on first boot and create a small social
graph (`person`, `post`, `knows`, `likes`) plus a `CREATE PROPERTY GRAPH social`.

| setting  | value       |
|----------|-------------|
| host     | `localhost` |
| port     | `5432`      |
| database | `graphlab`  |
| user     | `graph`     |
| password | `graphpass` |

## 2. Connect from DBCode (zero-config)

DBCode scans the workspace root and **auto-detects the `.env`** in this folder,
adding the connection for you (look for the 🧭 compass icon). Nothing to type.
→ https://dbcode.io/docs/connections/zero-config

Prefer to keep the password out of the connection? Use the included **`.pgpass`**
as an authentication profile instead:
→ https://dbcode.io/docs/authentication-profiles/pgpass
(The file is already `chmod 600`, which libpq/DBCode require.)

## 3. Experiment

Open **`graph-queries.sql`** as a SQL Notebook in DBCode and run the cells —
direct friendships, friend-of-a-friend, and graph patterns feeding plain SQL
aggregates.

## Useful commands

```bash
docker compose down        # stop, keep data
docker compose down -v     # stop, wipe data + re-run init/ scripts
docker compose exec postgres psql -U graph -d graphlab   # psql shell
```

## Reference

- Property Graphs — https://www.postgresql.org/docs/19/ddl-property-graphs.html
