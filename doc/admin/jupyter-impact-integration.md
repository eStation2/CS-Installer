***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 7 — JupyterNotebook and IMPACT Integration

**Version 1.0.0 — October 2026**

---

## 1. Overview

Climate Station integrates two companion applications, launched from the main
menu:

- **JupyterNotebook** (JupyterHub) — an interactive Python notebook environment
  for working with Climate Station data.
- **IMPACT** — the IMPACT Toolbox GIS application.

Both run as **separate containers** alongside the main application. This chapter
explains how each is launched and managed, and what an administrator needs to
know to keep them working.

## 2. Component layout

| Component | Container | Internal port | How it is reached |
|-----------|-----------|---------------|-------------------|
| Main application | `web` | 8080 | the normal Climate Station URL |
| JupyterHub | `jupyterhub` | 8000 | via the main app's reverse proxy at `/hub/` |
| IMPACT Toolbox | `impact5` | 8899 | directly on port **8899** (`IMPACT_PORT`) |

The main application reverse-proxies JupyterHub, so Jupyter is served under the
same host/port as Climate Station. IMPACT is reached on its own port.

## 3. JupyterNotebook (JupyterHub)

### 3.1 How it is launched

When a user clicks **JupyterNotebook** in the menu:

1. The main application issues a short-lived **JWT token** for the logged-in user.
2. A new browser window opens at `…/hub/?token=<jwt>`.
3. JupyterHub validates the token and logs the user in automatically (no second
   login prompt).
4. JupyterHub starts a **per-user notebook container** for that user.

### 3.2 What the administrator configures

| Setting | Where | Purpose |
|---------|-------|---------|
| `JWT_SECRET` | `.env` | Shared secret used to sign and validate the Jupyter login token. **Must be identical** on the main app and JupyterHub (both read the same `.env`). |
| `CS_NOTEBOOK_IMAGE` | `.env` | Docker image used for each user's notebook container. |

- `JWT_SECRET` must be a strong, secret string. If it is changed, both the `web`
  and `jupyterhub` containers must be restarted so they share the new value.
- JupyterHub runs in the `jupyterhub` container and spawns one notebook container
  per user on demand.

### 3.3 Operating it

```bash
# Is JupyterHub up?
docker ps | grep jupyterhub

# JupyterHub logs
docker logs --tail 100 jupyterhub

# Per-user notebook containers (spawned on demand)
docker ps | grep -i singleuser
```

### 3.4 Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Jupyter window opens but asks to log in / "403" | `JWT_SECRET` differs between `web` and `jupyterhub`, or was changed without restart | Set the same `JWT_SECRET` in `.env`; restart the application (`./cs_install.sh down && ./cs_install.sh up`) |
| Notebook fails to start | Notebook image missing/wrong, or Docker can't spawn | Check `CS_NOTEBOOK_IMAGE` exists; see `docker logs jupyterhub` |
| `/hub/` returns 502 | JupyterHub container down | Start it (`docker ps`), check its logs |
| Menu item not visible | Hidden for this user level / deployment mode | See Section 5 |

## 4. IMPACT Toolbox

### 4.1 How it is launched

When a user clicks **IMPACT**, the main application opens a new browser window
pointing at the IMPACT container:

```
http(s)://<same-host>:<IMPACT_PORT>/IMPACT
```

- The host is taken from the current Climate Station URL; the port is
  `IMPACT_PORT` (default **8899**).
- IMPACT is therefore served **directly on its own port**, not through the main
  application's reverse proxy. That port must be reachable from the user's
  browser.
- On the CLIMSA `double` / BBE deployment, IMPACT is instead reached under the
  current URL path (`…/IMPACT/`) rather than a separate port.

### 4.2 What the administrator configures

| Setting | Where | Purpose |
|---------|-------|---------|
| `IMPACT_PORT` | `.env` | External port where IMPACT is served (default 8899). The frontend builds the IMPACT link from this. |
| `IMPACT_HTTP_INTERNAL_PORT` | `.env` | IMPACT's internal port (default 9999). |

### 4.3 Operating it

```bash
# Is IMPACT up?
docker ps | grep impact5

# IMPACT logs
docker logs --tail 100 impact5
```

### 4.4 Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| IMPACT window blank / can't connect | Port `IMPACT_PORT` not reachable from the browser | Open/forward the port; verify `IMPACT_PORT` matches the running container |
| "Window already open" | A tab is already open for IMPACT | Switch to the existing window |
| Wrong host/port in the IMPACT link | `IMPACT_PORT` misconfigured | Set the correct `IMPACT_PORT` in `.env` and restart |
| Menu item not visible | Hidden for this user level / deployment mode | See Section 5 |

## 5. Menu visibility

The **JupyterNotebook** and **IMPACT** menu items are shown or hidden depending
on the user level and the deployment type. For example, on the hosted online
(`jrc_online`) deployment both are hidden. If a menu item does not appear, it is
usually because the current user or deployment mode does not expose it, not
because the service is down.

## 6. Notes

- Both are launched **in a new browser window/tab** from the main interface.
- JupyterHub shares the Climate Station host/port (via `/hub/`); IMPACT uses its
  own port (`IMPACT_PORT`), except on the `double`/BBE deployment where it is
  under the main URL path.
- Changing `JWT_SECRET`, `CS_NOTEBOOK_IMAGE`, or `IMPACT_PORT` requires restarting
  the affected containers.
