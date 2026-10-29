***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 2 — Setting the Portfolio via URL (`/portfolio/setportfolio`)

**Version 1.0.0 — October 2026**

---

## Contents

1. [Overview](#1-overview)
2. [What a portfolio is](#2-what-a-portfolio-is)
3. [The endpoint](#3-the-endpoint)
4. [Supported Regional Climate Centre codes](#4-supported-regional-climate-centre-codes)
5. [What happens when you call it](#5-what-happens-when-you-call-it)
6. [Before you run it](#6-before-you-run-it)
7. [How to run it](#7-how-to-run-it)
8. [After running it](#8-after-running-it)
9. [Troubleshooting](#9-troubleshooting)
10. [Reference](#10-reference)

---

## 1. Overview

A **portfolio** is the set of products a Climate Station instance is configured
to download, ingest, and process. Normally an administrator builds the portfolio
interactively in the **Portfolio** module of the web interface, selecting
products and mapsets one by one.

Climate Station also ships a shortcut that applies a **predefined portfolio for a
given Regional Climate Centre (RCC)** in a single HTTP call:

```
GET /portfolio/setportfolio?rcc=<RCC_CODE>
```

This is useful for provisioning a new installation to a known-good baseline — for
example when a partner such as **Tecnavia** sets up an instance for a specific
regional centre and wants the standard product set activated without clicking
through the UI.

> ⚠️ **This is not a read-only query.** Calling it **activates products and
> enables their ingestion, acquisition, and processing chains**, which starts
> downloads and processing. Read Section 5 and Section 6 before using it.

---

## 2. What a portfolio is

For each product the portfolio defines:

- whether the product is **activated**,
- its **subproducts**,
- for each subproduct, the **ingestion** configuration: the **native mapset**
  (the grid the data arrives in) and the **ingest mapset** (the regional grid it
  is clipped/reprojected to), plus whether that ingestion is enabled.

The predefined RCC portfolios bundle the standard product list for a region with
region-appropriate ingest mapsets already filled in (e.g. West-Africa grids for
AGRHYMET, East-Africa grids for ICPAC).

---

## 3. The endpoint

| Property | Value |
|----------|-------|
| Path | `/portfolio/setportfolio` |
| Methods | `GET`, `PUT` |
| Query parameter | `rcc` — Regional Climate Centre code (**required**) |
| Response | JSON: `{"success":"true","message":"Portfolio updated!"}` on success |
| Handler | `SetPortfolio()` → `SavePortfolio()` |

Full URL form (replace host/port with your deployment, as configured for this
machine):

```
http://<your-host>:<port>/portfolio/setportfolio?rcc=<RCC_CODE>
```

The `rcc` value is **case-insensitive** (it is upper-cased internally).

---

## 4. Supported Regional Climate Centre codes

Only the following `rcc` codes have a predefined portfolio. Any other value
results in no change and a failure message (see Section 9).

| `rcc` code | Regional Climate Centre | Typical regional focus |
|------------|-------------------------|------------------------|
| `ACMAD` | African Centre of Meteorological Applications for Development | Africa-wide |
| `AGRHYMET` | AGRHYMET Regional Centre | West Africa / Sahel (ECOWAS) |
| `ICPAC` | IGAD Climate Prediction and Applications Centre | East Africa / Horn of Africa |
| `CAPC` | Central Africa (Climate Application / Prediction Centre) | Central Africa |
| `SADC` | Southern African Development Community CSC | Southern Africa |
| `JRC` | Joint Research Centre reference set | Reference / global (also used for training centres, e.g. EAMAC, IMTR) |

> The exact product list and ingest mapsets for each code are defined in code
> (`SetPortfolio` in `webpy_esapp_helpers.py`). If a region needs a different set,
> that is a code/configuration change, not a parameter of this call.

> **Training centres:** the `JRC` reference set is also the one used for training
> centres such as **EAMAC** and **IMTR** — use `rcc=JRC` when provisioning those
> installations.

---

## 5. What happens when you call it

For the chosen `rcc`, the handler builds the predefined portfolio definition and
passes it to `SavePortfolio`. For **each product** in that definition it:

1. **Activates the product** (sets it active in the product catalogue).
2. **Enables / updates each ingestion** — writes the native and ingest mapset
   configuration for every subproduct.
3. **Updates the acquisitions** — so the download pipeline will fetch the product.
4. **Updates the processing chains** — so derived products (cumulations,
   anomalies, etc.) will be generated.

It then explicitly **activates the NDVI product** (`vgt-ndvi`).

Net effect: once the call returns `success: true`, the acquisition and processing
daemons will begin **downloading and processing** the whole regional product set
on their next cycle. On a fresh machine this can be a large, long-running
workload and significant disk usage.

---

## 6. Before you run it

Because this activates many products at once, check the following first:

- **Credentials.** Several products need data-provider credentials (NASA
  EarthData, Copernicus CDS/ADS/CDSE, Copernicus Marine, etc.). Configure these
  first, otherwise those downloads will fail. See the data-provider manual under
  `doc/user/` for how to create and enter credentials.
- **Disk space.** A full regional portfolio can require substantial storage under
  `/data`. Verify free space before enabling everything.
- **Network / proxy.** Ensure the machine can reach the data providers (direct or
  via the configured proxy).
- **Right RCC.** Pick the `rcc` that matches the installation's region — the
  ingest mapsets differ per region.
- **Existing portfolio.** This call activates its product set; it does not purge
  unrelated products you may already have activated. Review the Portfolio module
  afterwards to confirm the final state.

> Recommendation: run this on a freshly provisioned instance, or during a
> maintenance window, so the resulting download/processing burst is expected.

---

## 7. How to run it

Use any HTTP client. Examples (replace host/port to match the deployment):

**From a browser** — simply open:

```
http://<your-host>:<port>/portfolio/setportfolio?rcc=ICPAC
```

**With curl, from the host:**

```bash
curl -s "http://<your-host>:<port>/portfolio/setportfolio?rcc=ICPAC"
```

**With curl, from inside the container (useful for local testing):**

```bash
docker exec web sh -c "curl -s 'http://localhost:8080/portfolio/setportfolio?rcc=ICPAC'"
```

A successful response looks like:

```json
{"success":"true", "message": "Portfolio updated!"}
```

---

## 8. After running it

1. Open the **Portfolio** module in the web interface and confirm the expected
   products are activated.
2. Check the **Data Management** / completeness view to watch ingestion begin.
3. Monitor the acquisition and processing logs for errors (commonly missing
   credentials or network issues):

   ```bash
   docker exec web ls /data/static_data/log/
   docker exec web tail -50 /data/static_data/log/apps.acquisition.*.log
   docker exec web tail -50 /data/static_data/log/apps.processing.processing.log
   ```

4. If specific products should **not** be active, deactivate them individually in
   the Portfolio module.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `{"success":"false","message":"No portfolio passed to update!"}` | `rcc` missing, or not one of the supported codes (Section 4) | Pass a valid `rcc` value (case-insensitive) |
| HTTP error / 422 | `rcc` query parameter omitted entirely | Include `?rcc=<CODE>` |
| `{"success":"false","message":"Error updating the Portfolio!"}` | A product/ingestion/acquisition/chain update failed partway | Check acquisition/processing logs; verify DB connectivity and that referenced mapsets exist |
| Products activated but nothing downloads | Missing provider credentials or no network/proxy | Configure credentials (data-provider manual) and verify connectivity |
| Disk fills up after running | Full regional set enabled at once | Deactivate unneeded products in the Portfolio module; monitor `/data` |
| Call succeeds but some products you expected are absent | The predefined set for that `rcc` does not include them | Add them manually in the Portfolio module, or request a code update |

---

## 10. Reference

### 10.1 Endpoint

| Setting | Value |
|---------|-------|
| URL | `/portfolio/setportfolio?rcc=<RCC_CODE>` |
| Methods | `GET`, `PUT` |
| Supported `rcc` | `ACMAD`, `AGRHYMET`, `ICPAC`, `CAPC`, `JRC`, `SADC` |
| Success response | `{"success":"true", "message": "Portfolio updated!"}` |

### 10.2 Related endpoints

| URL | Purpose |
|-----|---------|
| `POST /portfolio` | Read the current portfolio (with optional theme/category/region filters) |
| `POST`/`PUT` `/portfolio/saveportfolio` | Save an arbitrary portfolio definition (JSON body) — the general form that `setportfolio` calls internally |
| `GET /portfolio/providers` | List data providers |
| `PUT /portfolio/providers/update` | Save provider credentials |

### 10.3 Related files (for maintainers)

- `src/fastapi_app/routers/products.py` — `/portfolio/setportfolio` route
  (`set_portfolio`).
- `src/webpy_esapp_helpers.py` — `SetPortfolio()` (predefined RCC portfolios) and
  `SavePortfolio()` (the generic apply logic).
- `src/database/querydb.py` — `get_portfolio()`, `active_product()`,
  `update_insert_ingestion()`.

### 10.4 Related documentation

- Data-provider credential creation: `doc/user/` (Data Provider manual).
