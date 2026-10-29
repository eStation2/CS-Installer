***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 5 — Dataset Completeness API (Third-Party Integration)

**Version 1.0.0 — October 2026**

---

## 1. Overview

Climate Station exposes HTTP endpoints that report, per dataset, **how many files
are present and how many are missing**, plus the date intervals of presence/gaps.
These are the same endpoints that feed Climate Station's own Data Management grid
and Dashboard. They can be consumed by third-party systems (for example, Tecnavia
machines) to monitor data availability.

Two endpoints are relevant:

| Endpoint | Purpose | Scope |
|----------|---------|-------|
| `GET /datshboard_datasetsinfo` | Aggregate present/missing totals + per-category counts | Whole instance (all history) |
| `GET /datasets` | Per-product / per-mapset / per-subproduct completeness and gaps | Windowed history (see Section 5) |

> The spelling `datshboard` (missing "a") is intentional and must be used exactly
> as shown — it is kept for backward compatibility.

Base URL: `http(s)://<your-host>[:<port>]` (the same host/port used to reach the
Climate Station web interface).

## 2. Summary endpoint — `/datshboard_datasetsinfo`

Returns overall counts across the whole instance: the total number of files
**present** vs **missing**, and the number of subproducts per category.

```
GET /datshboard_datasetsinfo
```

Example response (trimmed):

```json
{
  "success": "true",
  "datasetscompleteness": [
    { "completeness": "present", "value": 17031 },
    { "completeness": "missing", "value": 66181 }
  ],
  "datasetscategories": [
    { "category_id": "rainfall", "descriptive_name": "Rainfall (Monitoring)", "totsubproducts": "8" },
    { "category_id": "vegetation", "descriptive_name": "Vegetation", "totsubproducts": "13" }
  ]
}
```

Fields:

| Field | Meaning |
|-------|---------|
| `datasetscompleteness[].completeness` | `present` or `missing` |
| `datasetscompleteness[].value` | Total file count for that state across all datasets |
| `datasetscategories[]` | One entry per product category |
| `totsubproducts` | Number of subproducts in that category (string) |

Use this for a single, instance-wide "present vs missing" figure.

## 3. Detailed endpoint — `/datasets`

Returns the full breakdown: every activated product → its mapsets → its
subproducts, each carrying a `datasetcompleteness` object.

```
GET /datasets
```

Structure:

```
products[]
  └─ productmapsets[]
       └─ mapsetdatasets[]
            └─ datasetcompleteness   ← the counts and gaps you want
```

Each `datasetcompleteness` object:

```json
{
  "startdate": "2026-07-01",
  "firstdate": "2026-07-01",
  "lastdate":  "2026-10-21",
  "totfiles": 12,
  "missingfiles": 6,
  "intervals": [
    { "fromdate": "2026-07-01", "todate": "2026-08-21", "intervaltype": "present", "missing": false, "totfiles": 6, "intervalpercentage": 50.0 },
    { "fromdate": "2026-09-01", "todate": "2026-10-21", "intervaltype": "missing", "missing": true,  "totfiles": 6, "intervalpercentage": 50.0 }
  ]
}
```

Fields:

| Field | Meaning |
|-------|---------|
| `startdate` | Start of the window considered |
| `firstdate` / `lastdate` | First and last dates with data on disk |
| `totfiles` | Expected files in the window (present + missing) |
| `missingfiles` | Number missing |
| `intervals[]` | Contiguous runs of present/missing data |
| `intervaltype` / `missing` | `present` / `missing` (and boolean flag) |
| `totfiles` (per interval) | Files in that run |
| `intervalpercentage` | Share of the timeline that interval represents |

**Present files for a dataset** = `totfiles − missingfiles`.

To identify a dataset, read `productcode`, `version`, `mapsetcode`, and
`subproductcode` at the appropriate levels of the structure.

## 4. Freshness and the `force` parameter

Both endpoints are **cached** (24-hour refresh) so routine polling is fast. A
cached response is the normal, recommended mode.

Each endpoint also accepts `?force=true`, which **bypasses the cache and rescans
the disk**. This is **slow** (tens of seconds on a large instance) and should be
used sparingly.

```
GET /datasets?force=true                 # slow full rescan — avoid for polling
GET /datshboard_datasetsinfo?force=true  # heaviest — whole history
```

Guidance for third-party polling:

- Poll the **cached** endpoint (no `force`) — do not call `force=true` on a loop.
- Poll **at most** a few times per day; the data refreshes on a 24-hour cycle.
- Prefer `/datshboard_datasetsinfo` if you only need the overall present/missing
  totals; use `/datasets` when you need per-product detail.

## 5. Important: windowing of `/datasets`

`/datasets` only reports a **recent window** for high-frequency products, so older
data on disk is not counted there:

| Product frequency | Window shown by `/datasets` |
|-------------------|-----------------------------|
| Sub-daily (15 min / 30 min / hourly) | last few days |
| Daily | last 1 year |
| Dekadal / monthly / yearly | full history |

The summary endpoint `/datshboard_datasetsinfo` uses **full history** for daily
products (no 1-year window), so its totals can be larger than the sum visible in
`/datasets`. Choose the endpoint that matches what you need.

## 6. Quick test

```bash
# Summary (present vs missing totals)
curl -s "http://<your-host>:<port>/datshboard_datasetsinfo"

# Per-dataset detail
curl -s "http://<your-host>:<port>/datasets"
```

From inside the application container (local test):

```bash
docker exec web sh -c "curl -s 'http://localhost:8080/datshboard_datasetsinfo'"
```

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Request hangs / times out | Called with `?force=true` → full disk rescan | Use the cached endpoint (no `force`) for polling |
| 404 Not Found on the summary | Misspelled path | Use the exact spelling `datshboard_datasetsinfo` |
| Older data not counted in `/datasets` | Windowing (daily = last year, sub-daily = last days) | Use `/datshboard_datasetsinfo` for full-history totals |
| Totals look stale after new data arrives | 24-hour cache | Expected; data refreshes within a day (or call `force=true` once, sparingly) |
| `present` value seems low vs `missing` | `missingfiles` counts every expected-but-absent slot in the window | Expected — `present = totfiles − missingfiles` |

## 8. Notes

- These endpoints are **read-only** — they report on-disk availability and do not
  change any data.
- The counts reflect files produced by acquisition/ingestion/processing; a high
  `missing` count usually means data has not yet been downloaded/processed for
  those dates (see Chapter 2 on provisioning the product portfolio).
