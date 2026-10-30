***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

**Version 1.0.0 — October 2026**

---

## Scope

This manual is for system administrators who install, configure, and operate a
Climate Station deployment installed with this installer (the `CS-Installer`
package). End-user workflows (data analysis, graphs) are covered separately in
the user manuals.

> **Security notice (public repository):** this repository is public. **Do not
> commit any real credentials** — no passwords, API keys, tokens, or secrets — in
> these documents or in committed configuration. Where a default value exists in
> shipped configuration, change it on your deployment and keep the real value
> only in your local `.env` (which is not committed).

## Conventions

- Commands on the **host** are shown as plain shell commands, run from the
  installation directory (where `.env`, `docker-compose.yml`, and `cs_install.sh`
  live), referred to as `<cs_installer_dir>`.
- Commands inside the application container are prefixed with `docker exec web …`.
- The application is started and stopped with **`cs_install.sh`** (see below).

## Starting and stopping the application

This installer uses the `cs_install.sh` script:

```bash
cd <cs_installer_dir>

# Start (default action)
./cs_install.sh up          # or simply: ./cs_install.sh

# Stop
./cs_install.sh down

# Restart
./cs_install.sh down && ./cs_install.sh up

# First-time install / apply updates
./cs_install.sh -i          # --init
```

Image source options when installing/pulling:

```bash
./cs_install.sh -p          # pull images from the public registry
./cs_install.sh -j          # pull images from the JRC registry
```

`up` starts the Docker Compose stack (`web`, `postgres`, `jupyterhub`) and also
starts the **IMPACT** container; `down` stops the stack, the IMPACT container, and
any running notebook containers.

## Chapters

| # | Chapter | Covers |
|---|---------|--------|
| 1 | [OGC WMS/WCS Configuration](./ogc-wms-wcs-configuration.md) | Serving products as OGC Web Map / Web Coverage Services |
| 2 | [Setting the Portfolio via URL](./portfolio-setportfolio.md) | Provisioning a predefined regional product set |
| 3 | [User Management](./user-management.md) | Self-registration and database procedures for user accounts |
| 4 | [Connecting a Database Viewer](./database-viewer.md) | Connecting pgAdmin / DBeaver (or psql) to the database |
| 5 | [Dataset Completeness API](./dataset-completeness-api.md) | Third-party integration — present/missing file counts per dataset |
| 6 | [Ingesting Historical Archives](./historical-archive-ingestion.md) | Starting archive ingestion and monitoring its status |
| 7 | [JupyterNotebook and IMPACT Integration](./jupyter-impact-integration.md) | How the notebook environment and IMPACT Toolbox are launched |
| 8 | [Log Files and Troubleshooting](./log-files.md) | Where each component's logs live and which to read |
| 9 | [Checking Containers and Services](./container-health.md) | Verifying containers are up/healthy and start/stop/restart |
| 10 | [Installation Type, Role, and Mode](./installation-type-role-mode.md) | Deployment type, and the `role`/`mode` (Current mode) settings for the two-machine (double/Tecnavia) setup |
| 11 | [Bucardo Database Synchronisation](./bucardo-db-sync.md) | How the two-machine (double) databases are kept in sync, how it is controlled, and how to check it |
