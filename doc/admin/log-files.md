***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 8 — Log Files and Troubleshooting

**Version 1.0.0 — October 2026**

---

## 1. Overview

Climate Station writes detailed logs for each component. When something is not
working — a product not downloading, processing not running, the web app
erroring — the logs are the first place to look. This chapter lists where the
logs are, how they are named, and which log to read for each kind of problem.

## 2. Where the logs are

| Location | Contents |
|----------|----------|
| `/data/static_data/log/` (in the `web` container) | **Main application logs** — one file per Python module (acquisition, processing, analysis, web services, MapServer errors, etc.) |
| `/var/log/uvicorn/` (in the `web` container) | Web server (uvicorn) access and error logs |
| PostgreSQL container logs | Database server logs (via `docker logs postgres`) |

On the host, the application log directory is also available under the
installation's `log/` folder (`log/web`, `log/postgres`, `log/mapserver`),
mounted from the containers.

### Naming convention

Most application log files are named after the Python module that writes them:

```
/data/static_data/log/<module.dotted.path>.log
```

For example `apps.acquisition.ingestion.log`,
`apps.processing.processing.log`, `apps.analysis.getTimeseries.log`.

### Log rotation

Log files rotate automatically when they reach a size limit, keeping a few
numbered backups (`.log.1`, `.log.2`, `.log.3`). Always read the base `.log` file
for the most recent entries.

## 3. Which log for which component

### Data download (acquisition)

| Problem | Log file |
|---------|----------|
| General internet downloads | `apps.acquisition.get_internet.log` |
| A specific internet source | `apps.get_internet.<DATASOURCE_ID>.log` |
| CDS / ADS / IRI (datastore) downloads | `apps.acquisition.get_datastore.log` |
| A specific datastore source | `apps.get_datastore.<DATASOURCE_ID>.log` |
| EUMETCast reception | `apps.acquisition.get_eumetcast.log` and `apps.get_eumetcast.<DATASOURCE_ID>.log` |

### Ingestion

| Problem | Log file |
|---------|----------|
| General ingestion | `apps.acquisition.ingestion.log` |
| File placement | `apps.acquisition.ingestion_ingest_file.log` |
| NetCDF ingestion | `apps.acquisition.ingestion_netcdf.log` |
| Pre-processing (reproject/rescale) | `apps.acquisition.ingestion_pre_process.log` |

### Processing (derived products)

| Problem | Log file |
|---------|----------|
| Processing service (overall) | `apps.processing.processing.log` |
| A specific processing chain | `apps.processing.ID=<N>_PROD=<product>_METHOD=<method>_ALGO=<algo>.log` |

Example chain log:
`apps.processing.ID=1000_PROD=arc2-rain_METHOD=proc_precip_1day_ALGO=proc_precip_1day.log`

### Analysis and web services

| Problem | Log file |
|---------|----------|
| Timeseries / graph extraction | `apps.analysis.getTimeseries.log` |
| WMS requests | `mapserver_wms_layer_errors.log` |
| WCS requests | `mapserver_wcs_layer_errors.log` |
| General MapServer errors | `mapserver_error.log` |
| Web interface backend handlers | `webpy_esapp_helpers.log` |

### System services

| Problem | Log file |
|---------|----------|
| System service daemon (sync, cleanup, dumps) | `apps.es2system.es2system.log` |
| Historical archive ingestion | `apps.es2system.ingest_archive.log` |
| SPIRITS conversion | `apps.es2system.convert_2_spirits.log` |
| FTP push | `apps.es2system.push_data_ftp.log` |

### Web server and database

| Problem | Where |
|---------|-------|
| Web server errors (5xx, startup) | `/var/log/uvicorn/climatestation_error.log` |
| Web server access log | `/var/log/uvicorn/climatestation_access.log` |
| Database server | `docker logs postgres` |

### Companion applications

| Problem | Where |
|---------|-------|
| JupyterHub / notebooks | `docker logs jupyterhub` |
| IMPACT Toolbox | `docker logs impact5` |

## 4. How to read the logs

```bash
# Follow a log live (Ctrl-C to stop)
docker exec web tail -f /data/static_data/log/apps.processing.processing.log

# Last 50 lines
docker exec web tail -50 /data/static_data/log/apps.acquisition.ingestion.log

# Search a log for problems
docker exec web grep -iE 'error|exception|failed' \
  /data/static_data/log/apps.acquisition.get_internet.log | tail -20

# List the most recently updated logs (what is active right now)
docker exec web sh -c "ls -lt /data/static_data/log/ | head -20"

# Web server errors
docker exec web tail -50 /var/log/uvicorn/climatestation_error.log

# Database / companion containers
docker logs --tail 100 postgres
docker logs --tail 100 jupyterhub
docker logs --tail 100 impact5
```

Tips:
- When unsure which log, list the directory by modification time
  (`ls -lt`) — the file being written to now is usually the one you want.
- Search for `error`, `exception`, `failed`, or `traceback` to jump to problems.
- Note the timestamp of the issue and correlate across logs (e.g. a download log
  and the ingestion log).

## 5. Typical troubleshooting flow

| Problem reported | Start with |
|------------------|-----------|
| A product has no new data | `get_internet` / `get_datastore` (download) → `ingestion` (if downloaded but not placed) |
| Derived product (anomaly, cumulation) missing | `apps.processing.processing.log`, then the specific chain log |
| Map not drawing / WMS error | `mapserver_wms_layer_errors.log` |
| Download / coverage (WCS) error | `mapserver_wcs_layer_errors.log` |
| Graph / timeseries empty or wrong | `apps.analysis.getTimeseries.log` |
| Web interface shows an error / 500 | `/var/log/uvicorn/climatestation_error.log`, then `webpy_esapp_helpers.log` |
| Archive ingestion not progressing | `apps.es2system.ingest_archive.log` |
| Notebooks won't open | `docker logs jupyterhub` |

## 6. Notes

- Logs are the primary diagnostic tool — capture the relevant log excerpt
  (with timestamps) when reporting an issue.
- A missing per-source or per-chain log usually means that source/chain has not
  run yet.
- For download credential problems, the download log (`get_internet` /
  `get_datastore`) shows authentication errors — enter provider credentials in the
  Data Provider dialog (see the user Data Provider manual).
