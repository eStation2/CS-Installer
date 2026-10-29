***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 4 — Connecting a Database Viewer (pgAdmin / DBeaver)

**Version 1.0.0 — October 2026**

---

## 1. Overview

Climate Station stores its configuration and metadata in a PostgreSQL/PostGIS
database running in the `postgres` container. Administrators sometimes need to
inspect or edit this data directly (for example to change a user password, see
Chapter 3). This chapter explains how to connect a database viewer such as
**pgAdmin** or **DBeaver** to that database.

> ⚠️ Direct database access bypasses the application's safeguards. Use it for
> inspection and documented procedures only, always with care.

## 2. Connection parameters

The connection details come from `.env` and the installer's `docker-compose.yml`:

| Setting | Value | Source |
|---------|-------|--------|
| **Host** | the server running Climate Station (`localhost` if the viewer runs on the same machine) | — |
| **Port** | `5431` (default) | `.env` → `CS_PGPORT` |
| **Database** | `estationdb` | compose |
| **Username** | `estation` | compose |
| **Password** | the configured database password (see your `.env` / compose) | compose |

> **Do not share or publish the database password.** Look it up in your local
> configuration; it is not reproduced in this manual.

> **Port note:** the container's internal PostgreSQL port is `5432`, but it is
> published on the host as `CS_PGPORT` (default **5431**). From a viewer on the
> host, connect to port **5431**. Check your `.env` if it was changed.

> **Remote access:** if the viewer runs on a different machine, use the server's
> hostname/IP as the host and ensure the `CS_PGPORT` port is reachable (firewall).
> The port is only exposed if the deployment allows it.

## 3. Connect with pgAdmin

1. Open pgAdmin → right-click **Servers** → **Register → Server…**
2. **General** tab: Name = `Climate Station` (any label).
3. **Connection** tab:
   - Host name/address: `localhost` (or the server IP)
   - Port: `5431`
   - Maintenance database: `estationdb`
   - Username: `estation`
   - Password: the configured database password
4. **Save**. Expand the server →
   `Databases → estationdb → Schemas` to browse.

## 4. Connect with DBeaver

1. **Database → New Database Connection → PostgreSQL**.
2. Fill:
   - Host: `localhost` (or server IP)
   - Port: `5431`
   - Database: `estationdb`
   - Username: `estation`
   - Password: the configured database password
3. **Test Connection**, then **Finish**. Browse under
   `estationdb → Schemas`.

## 5. Where the data lives

The data is organised into three schemas:

| Schema | Contents |
|--------|----------|
| `products` | Products, subproducts, mapsets, acquisition sources, data providers, processing chains |
| `analysis` | Users, layers, workspaces, graph/map templates, legends |
| `climsoft` | Weather-station observation data (where used) |

For example, user accounts are in `analysis.users` (see Chapter 3), and data
provider credentials are in `products.provider`.

## 6. Alternative: command line (no viewer)

If no GUI is available, open a session directly inside the container:

```bash
docker exec -it postgres psql -U estation -d estationdb
```

List schemas and tables at the `psql` prompt:

```sql
\dn                 -- list schemas
\dt analysis.*      -- list tables in the analysis schema
```

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Connection refused / timeout | Wrong port, or port not exposed/reachable | Use `CS_PGPORT` (default 5431); check firewall for remote access |
| Password authentication failed | Wrong username/password | Use `estation` and the configured database password |
| Database "estationdb" does not exist | Wrong database name | Connect to `estationdb` |
| Can't see tables | Browsing the wrong schema | Expand `products` / `analysis` / `climsoft` |
| Works in container but not from host | Connecting to 5432 instead of the published port | Use the host-published port `CS_PGPORT` (5431) |

## 8. Security notes

- The shipped configuration uses default credentials — **change the database
  password** on any real deployment, and restrict who can reach the database port,
  especially on internet-facing servers.
- Prefer read-only inspection; make edits only for documented procedures.
- The database contains sensitive values (user passwords, provider credentials)
  in plaintext — treat exports and screenshots accordingly.
