***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 11 — Bucardo Database Synchronisation (double deployment)

**Version 1.0.0 — October 2026**

---

## 1. Overview

On a **two-machine (`double`) deployment** — such as the Tecnavia setup — two
Climate Station installations work as a pair: a **processing** machine and an
**analysis** machine. Their PostgreSQL databases are kept in sync using
**Bucardo**, an asynchronous multi-master replication tool for PostgreSQL.

This chapter explains, at an operator level, what Bucardo does, how it is
controlled, and how to check/troubleshoot it. Bucardo is used **only** on
`double` installations; on `full` / `Server` / `SinglePC` / `jrc_online` there is
no DB sync and this chapter does not apply.

> See Chapter 10 for installation type, role, and mode — the settings that
> control whether and how Bucardo runs.

## 2. What is synchronised

Each machine replicates the schemas it "owns" to the other:

| Role | Schemas this machine is the source of |
|------|---------------------------------------|
| `processing` | `products`, `climsoft` |
| `analysis` | `analysis` |

So the processing machine pushes product/configuration and climsoft data to the
analysis machine, and the analysis machine pushes analysis data (users,
workspaces, templates, legends, layers) back. Together the pair stays consistent.

## 3. What controls whether sync runs

Bucardo is driven by the **system service** inside the `web` container, based on
the deployment's **mode** (see Chapter 10):

| Mode | Sync behaviour |
|------|----------------|
| `nominal` | Bucardo runs and replication is active — provided the paired machine is also healthy. |
| `recovery` | Sync is **suspended** (the machine is recovering; avoids conflicts). |
| `maintenance` | Sync is **stopped**. |

Additionally, in `nominal` mode the service checks the **paired machine's**
status: if the peer reports `recovery` or is unreachable, sync is held off to
avoid conflicting changes.

The system service starts/stops Bucardo automatically according to these rules —
an operator normally does not start Bucardo by hand.

## 4. Checking Bucardo status

Bucardo runs against the database. To see its status, open a shell in the
database container and query Bucardo:

```bash
docker exec -it postgres bash
bucardo -d bucardo -U estation status
```

(You will be prompted for, or must provide, the Bucardo DB password — use the one
configured for your deployment; it is not reproduced here.)

A healthy pair shows the configured **sync** (e.g. `sync_thispc`) with recent
activity and no large backlog. The relevant log directories inside the container
are `/var/log/bucardo/` (Bucardo's own logs) and the system service log
(`/data/static_data/log/apps.es2system.es2system.log`) for the start/stop
decisions.

## 5. Normal lifecycle

1. **Initialisation** — Bucardo is installed and its databases/syncs are created
   when the installation is first set up (part of the container initialisation
   for a `double` deployment). The sync definition is based on the machine's
   **role** and the paired machine's address.
2. **Operation** — while in `nominal` mode, the system service keeps Bucardo
   running and replication flows both ways.
3. **Recovery / maintenance** — switching a machine to `recovery` or
   `maintenance` mode stops its sync (Chapter 10, Section 6).
4. **Upgrades** — when the product set / database structure changes, Bucardo
   definitions are **reset and recreated** so the new tables are included. This is
   handled by the installer/system service, not manually.

## 6. Prerequisites for the pair to sync

- Both machines are `double` installations with **opposite roles**
  (`processing` and `analysis`).
- Each machine knows the other's address (the paired-machine setting).
- The machines can reach each other's PostgreSQL port over the network
  (firewall/hosts configured).
- Both machines are in `nominal` mode.

## 7. Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| No data appears on the paired machine | One side not in `nominal`, or peer unreachable | Set both machines to `nominal`; verify network reachability between them (Chapter 10) |
| `bucardo status` shows no syncs | Bucardo not yet configured on this machine | Confirm this is a `double` install with a role set; the sync is created during initialisation |
| Sync stopped after an upgrade | Definitions reset for the new tables, not yet recreated | The system service recreates them; check the system service log |
| Changes conflict / unexpected overwrites | Both machines edited the same schema, or roles misconfigured | Ensure each schema is owned by exactly one role (Section 2); fix roles |
| Replication lag / backlog | Network issues or a machine was down | Restore connectivity; Bucardo catches up once both are healthy and `nominal` |

Where to look:

```bash
# Bucardo's own logs (inside the postgres container)
docker exec postgres sh -c "ls -lt /var/log/bucardo/ | head"

# System service decisions (start/stop sync) inside the web container
docker exec web tail -50 /data/static_data/log/apps.es2system.es2system.log
```

## 8. Notes

- Bucardo and its sync lifecycle are **managed automatically** by the system
  service based on role and mode — avoid starting/stopping or reconfiguring it by
  hand on a production pair unless following a documented recovery procedure.
- Coordinate any mode/role change across **both** machines (Chapter 10).
- This applies only to `double` deployments; standalone installations do not run
  Bucardo.
