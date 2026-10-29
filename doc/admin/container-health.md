***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 9 — Checking Containers and Services

**Version 1.0.0 — October 2026**

---

## 1. Overview

Climate Station runs as a set of Docker containers. This chapter explains how to
check that they are up and healthy, and how to start, stop, and restart the
application. For reading component logs once a container is up, see Chapter 8.

## 2. The containers

A running installation has these containers:

| Container | Role | Published port |
|-----------|------|----------------|
| `web` | Main application (web interface, APIs, acquisition/ingestion/processing services) | 8080 |
| `postgres` | PostgreSQL/PostGIS database | 5431 (host) → 5432 |
| `jupyterhub` | JupyterHub (notebook environment) | internal |
| `impact5` | IMPACT Toolbox | 8899 |

> Per-user notebook containers (names starting `jupyter-`) are created on demand
> by JupyterHub and appear only while a user has a notebook session open.

## 3. Check that containers are up

```bash
docker ps
```

A healthy system shows `web`, `postgres`, `jupyterhub`, and `impact5` with status
`Up …`. The `postgres` container also reports `(healthy)` once its health check
passes.

Useful variations:

```bash
# Compact view with ports and status
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Include stopped containers (did one exit/crash?)
docker ps -a

# Check one container
docker ps --filter name=web
```

If a container is **missing** from `docker ps` or shows `Exited`, it is down —
check its logs (Section 6) and restart the application (Section 5).

## 4. Check that the application responds

Beyond "the container is up", confirm the web application actually answers:

```bash
# Should return HTTP 200
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/

# Database health (from the host)
docker exec postgres pg_isready -U estation -d estationdb
```

Or simply open the Climate Station URL in a browser.

## 5. Start, stop, restart

Use the `cs_install.sh` script in the installation directory (do **not** run it as
root/sudo):

```bash
cd <cs_installer_dir>

# Start the Climate Station (up is the default action)
./cs_install.sh up

# Stop (stops the stack, the IMPACT container, and notebook containers)
./cs_install.sh down

# Restart
./cs_install.sh down && ./cs_install.sh up
```

Optional flags (see `./cs_install.sh --help`):

- `-u | --user <uid>` and `-g | --group <gid>` — run with a specific host user/group id
  (file-permission mapping).
- `-i | --init` — first-time install / apply updates.
- `-p | --pull` / `-j | --jrc` — pull images from the public / JRC registry.

To restart a **single** container without stopping everything:

```bash
docker restart web          # or postgres / jupyterhub / impact5
```

> - `up` starts the Compose stack (`web`, `postgres`, `jupyterhub`) and also
>   launches the `impact5` container.
> - `down` stops the Compose stack, stops and removes `impact5`, and stops any
>   running `jupyter-*` notebook containers.
> - Changes to `.env` take effect only after the application is restarted
>   (`down` then `up`).

### 5.1 Tecnavia (BBE) deployment

On the Tecnavia BBE deployment the installer lives at
`/tecnavia/other/CS-Installer/` and is started with an explicit user/group id
(1000/1000):

```bash
# Stop
/tecnavia/other/CS-Installer/cs_install.sh down

# Start
/tecnavia/other/CS-Installer/cs_install.sh up -g 1000 -u 1000
```

Use these exact commands on Tecnavia machines; the `-g 1000 -u 1000` flags set the
host user/group id so data file permissions are correct.

## 6. If a container is down or unhealthy

1. Confirm which one: `docker ps -a` (look for missing or `Exited` containers).
2. Read its logs:
   ```bash
   docker logs --tail 100 web
   docker logs --tail 100 postgres
   docker logs --tail 100 jupyterhub
   docker logs --tail 100 impact5
   ```
   (For the application's internal component logs — acquisition, processing, etc.
   — see Chapter 8.)
3. Restart it (`docker restart <name>`) or restart the whole stack (Section 5).
4. If `web` depends on `postgres`, make sure `postgres` is **healthy** first —
   `web` waits for the database to be ready.

## 7. Resource usage (optional)

```bash
docker stats --no-stream     # CPU/memory/IO per container
df -h                        # host disk (data accumulates under the data volume)
```

## 8. Troubleshooting

| Symptom | Check | Action |
|---------|-------|--------|
| Web interface unreachable | `docker ps` — is `web` up? | Restart with `cs_install.sh`; read `docker logs web` and the web server log (Chapter 8) |
| `web` keeps restarting | `docker logs web`; is `postgres` healthy? | Fix the database first; `web` depends on it |
| Database errors everywhere | `docker exec postgres pg_isready …` | Restart; check `docker logs postgres` |
| Notebooks won't open | Is `jupyterhub` up? | `docker logs jupyterhub`; see Chapter 7 |
| IMPACT won't open | Is `impact5` up and port 8899 reachable? | `docker logs impact5`; see Chapter 7 |
| Everything slow | `docker stats`, `df -h` | Check CPU/memory and free disk on the host |

## 9. Notes

- Starting/stopping is handled by `cs_install.sh`, which uses the installer's
  `docker-compose.yml`.
- Container names are fixed (`web`, `postgres`, `jupyterhub`, `impact5`), so the
  commands above work on any standard installation.
- On Tecnavia (BBE) machines, always use the `/tecnavia/other/CS-Installer/`
  path and the `-g 1000 -u 1000` flags shown in Section 5.1.
