***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 6 — Ingesting Historical Archives

**Version 1.0.0 — October 2026**

---

## 1. Overview

Historical archives are pre-generated raster files (produced on a reference
machine and placed under `/data/archives`) that can be **re-ingested** into a
deployed instance to backfill its product history. Ingestion is started from the
**System Settings** page of the web interface and runs as a **background
service**.

This chapter explains how to start/stop it and — the main question — how to
monitor its status.

## 2. Starting ingestion from the interface

1. Confirm the archive files are present under `/data/archives` on the server.
2. In the web interface, open **System Settings**.
3. Find the **Ingest Archive** action and choose **Run** (start). You can also
   **Stop** or **Restart** it from the same place.

What happens: this starts a background **ingest-archive service**. The service
scans `/data/archives` and ingests the matching files into `/data/processing`.
The archive files are **not deleted** after ingestion.

> Ingestion is **asynchronous**: starting it returns immediately while the work
> continues in the background. It is not instantaneous — monitor it as described
> below.

## 3. Using the API directly (`POST /systemsettings/ingestarchive`)

The System Settings buttons call a single endpoint. You can call it directly
(for scripting or from another machine) — it is the same action.

```
POST /systemsettings/ingestarchive
```

It is a **service controller**: it starts/stops the background ingest-archive
service. It does not ingest files itself — the service does that asynchronously.

**Form parameter:**

| Field | Values | Meaning |
|-------|--------|---------|
| `task` | `run` / `stop` / `restart` | `run` = start the service, `stop` = stop it, `restart` = stop then start |

### Start ingestion

```bash
curl -s -X POST -d 'task=run' http://<your-host>:<port>/systemsettings/ingestarchive
```

- If the service is not already running, it is started and begins ingesting.
- If it is already running, nothing extra happens ("was already up").

### Stop / restart

```bash
curl -s -X POST -d 'task=stop'    http://<your-host>:<port>/systemsettings/ingestarchive
curl -s -X POST -d 'task=restart' http://<your-host>:<port>/systemsettings/ingestarchive
```

### Response

Every call returns the service's current state:

```json
{ "success": "true", "running": "true", "message": "Ingest Archive service was already up" }
```

| Field | Meaning |
|-------|---------|
| `success` | `"true"` if the request was handled |
| `running` | `"true"` = service active (still ingesting); `"false"` = finished or not started |
| `message` | Human-readable result (e.g. "started", "was already up", "stopped") |

> There is no separate `task=status`. To **check status**, simply send
> `task=run` again and read the `running` field — if it is still `"true"` the
> ingestion is ongoing; once it is `"false"` the run has completed (the service
> stops itself when done). See Section 4 for log-based monitoring.

From inside the application container (local test):

```bash
docker exec web sh -c "curl -s -X POST -d 'task=run' http://localhost:8080/systemsettings/ingestarchive"
```

## 4. Monitoring the status

There is **no progress bar or percentage** for an ingestion run. Use one of the
following to see whether it is still running and how far it has got.

### 4.1 Running state (interface / API response)

Each time you trigger the action, the response reports whether the service is
running:

```json
{ "success": "true", "running": "true", "message": "Ingest Archive service was already up" }
```

- `running: "true"` → the service is **still ingesting**.
- `running: "false"` → it has **finished** (the service stops itself when done),
  or it was never started.

To check again later, trigger **Run** once more: if it is still busy you get
"was already up" with `running:true`; once it has finished, you get
`running:false`. (This is the simplest check from the interface.)

### 4.2 Service status from the command line

On the server:

```bash
docker exec web python /var/www/climatestation/apps/es2system/service_ingest_archive.py status
```

### 4.3 Log file (recommended for real progress)

The log shows each product/subproduct being ingested and any errors — the best
way to see progress and confirm completion:

```bash
docker exec web tail -f /data/static_data/log/apps.es2system.ingest_archive.log
```

When ingestion finishes, log activity stops and the service reports
`running:false`.

> **Note:** the general **Services status** panel (eumetcast / internet /
> ingestion / processing) does **not** include the archive-ingestion service, so
> it cannot be used to monitor this task. Use the three methods above.

## 5. Stopping ingestion

From **System Settings**, choose **Stop** on the Ingest Archive action (or send
`task=stop` to the API, Section 3). The response message confirms whether it was
running and has been stopped.

## 6. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Nothing seems to happen after "Run" | Ingestion runs in the background; it is not immediate | Check the log / `running` flag (Section 4) |
| `running` stays `true` for a long time | Large archive set still being ingested | Tail the log to confirm progress; wait for it to finish |
| Files not ingested | Archive files not under `/data/archives`, or names don't match the expected pattern | Verify the files are present and named in the standard Climate Station format |
| Archive folder never shrinks | Ingestion does not delete source archives (by design) | Expected |
| Can't find status in the Services panel | That panel does not track archive ingestion | Use the log or the `running` flag |

## 7. Notes

- Ingestion writes into the normal product storage (`/data/processing`), so
  ingested history appears in the application like any other data (and in the
  completeness reports — see Chapter 5).
- Only one ingest-archive service runs at a time; starting it when already up has
  no extra effect.
