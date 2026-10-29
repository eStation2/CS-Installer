***Intra-ACP Climate Service and related applications (ClimSA)***

**Climate Station — Administration Manual**

# Chapter 1 — OGC WMS/WCS Configuration

**Version 1.0.0 — October 2026**

---

## Contents

1. [Overview](#1-overview)
2. [Prerequisite: set the service base URL (`OWS_ONLINE_URL`)](#2-prerequisite-set-the-service-base-url-ows_online_url)
3. [How the base URL reaches the service](#3-how-the-base-url-reaches-the-service)
4. [Enabling a product for WMS/WCS](#4-enabling-a-product-for-wmswcs)
5. [Verifying the service](#5-verifying-the-service)
6. [Using the services from a client](#6-using-the-services-from-a-client)
7. [Troubleshooting](#7-troubleshooting)
8. [Reference](#8-reference)

---

## 1. Overview

Climate Station publishes its processed raster products as **OGC web services**
so that external clients (QGIS, ArcGIS, GDAL, web map viewers) can consume them
over standard protocols:

- **WMS** (Web Map Service) — rendered map images (PNG/JPEG/GIF) with legends.
- **WCS** (Web Coverage Service) — the underlying raster data as GeoTIFF.

Both are served by a **single endpoint**:

```
http(s)://<your-host>[:<port>]/webservices
```

Internally the endpoint is handled by FastAPI, which dispatches to MapServer
(via `mapscript`) to render the requested layer. The raster files themselves
live under `/data/processing` and are selected entirely from database values —
clients never supply a filesystem path.

Supported requests:

| Service | Requests |
|---------|----------|
| WMS | `GetCapabilities`, `GetMap`, `GetFeatureInfo`, `GetLegendGraphic`, `DescribeLayer`, `GetStyles` |
| WCS | `GetCapabilities`, `GetCoverage`, `DescribeCoverage`, `GetMetadata` (1.0.0 / 1.1.1 / **2.0.1 default**) |

There are two independent things an administrator must get right:

1. **Server level** — the service must advertise the *correct public URL* so
   clients know where to send follow-up requests. This is the `OWS_ONLINE_URL`
   setting (Section 2). **This is the step most commonly missed on a new
   deployment.**
2. **Product level** — each product must be *enabled* for web services
   (Section 4).

---

## 2. Prerequisite: set the service base URL (`OWS_ONLINE_URL`)

### 2.1 What it is

`OWS_ONLINE_URL` is an environment variable that defines the **OnlineResource
URL** advertised in the `GetCapabilities` response. When a client fetches
Capabilities, every `<OnlineResource xlink:href="...">` element tells it where to
send the next request (`GetMap`, `GetCoverage`, `GetLegendGraphic`). If this URL
is wrong, Capabilities may still load, but **map and coverage requests will be
directed to the wrong host** and fail.

### 2.2 Why you must set it

If `OWS_ONLINE_URL` is **not** set, the service falls back to a hardcoded default:

```
https://estation.jrc.ec.europa.eu/eStation3/webservices
```

This default is correct **only** on the JRC production server. On any other
machine it points clients at JRC instead of your server. Therefore **every
non-JRC deployment must set `OWS_ONLINE_URL` explicitly.**

> ⚠️ **Gotcha:** the shipped `.env.template` lists `OWS_ONLINE_URL` but leaves it
> **empty**. A fresh install that copies the template without editing this line
> will silently inherit the JRC default.

### 2.3 How to set it

1. Open the `.env` file in the installation root:

   ```bash
   cd <climatestation_dir>
   vi .env
   ```

2. Set `OWS_ONLINE_URL` to the **public URL of this machine's `/webservices`
   endpoint**. It must match how clients actually reach the server — the real
   hostname / alias / IP, the external port, and `http` vs `https` (including any
   reverse proxy path prefix).

   ```env
   # OWS (WMS/WCS) OnlineResource URL used in GetCapabilities responses.
   OWS_ONLINE_URL=http://my-host.example.org:8080/webservices
   ```

   Examples:

   | Deployment | Value |
   |------------|-------|
   | Direct host access on port 8080 | `http://my-server:8080/webservices` |
   | Behind an HTTPS reverse proxy with a path prefix | `https://my-host.example.org/eStation3/webservices` |
   | Local test only | `http://localhost:8080/webservices` |

   Notes:
   - Always end the path with `/webservices`.
   - A trailing `?` is **not** required (the service adds query parameters).
   - Do **not** use `localhost` for a value that external clients must reach —
     they cannot resolve your container's `localhost`.

3. Apply the change by restarting the application (environment variables are
   read at container start):

   ```bash
   ./cs_install.sh down && ./cs_install.sh up
   ```

   > Editing `.env` alone does **not** affect a running container. You must
   > restart it.

> **Version note:** `OWS_ONLINE_URL` is supported by recent Climate Station
> images. If it is **not** present in your `.env.template`, your image may predate
> this setting — in that case the OnlineResource uses the built-in default and
> cannot be overridden via `.env`. Add the variable only if your version supports
> it.

---

## 3. How the base URL reaches the service

Understanding the path helps when debugging. The value flows from `.env` all the
way into the Capabilities XML:

```
.env  (OWS_ONLINE_URL=...)
   │   the `web` service in docker-compose.yml uses: env_file: ./.env
   ▼
web container environment   (every key in .env is injected automatically)
   │   WMS.py / WCS_refactored.py call os.environ.get('OWS_ONLINE_URL', <JRC default>)
   ▼
MapServer metadata   (wms_onlineresource / ows_onlineresource / wcs_onlineresource)
   │
   ▼
GetCapabilities XML   (<OnlineResource xlink:href="...">)
```

Two consequences worth noting:

- Because the `web` service uses `env_file: ./.env`, **any** variable placed in
  `.env` is available inside the container. `OWS_ONLINE_URL` does **not** need its
  own entry under the compose `environment:` block.
- The same variable is read by **both** the WMS handler and the (active) WCS
  handler, so a single setting configures both services consistently.

---

## 4. Enabling a product for WMS/WCS

Setting `OWS_ONLINE_URL` makes the *service* reachable, but it does **not** make
any particular product appear. The `/webservices` endpoint is always active; a
subproduct is exposed only when **all** of the following are true:

| Condition | Where |
|-----------|-------|
| Parent product `(productcode, version)` is **activated** | `products.product` |
| Subproduct is **not masked** (`masked = 'f'`) | `products.sub_product` |
| Subproduct has the **web-services flag** set (`mobile_app = 't'`) | `products.sub_product` |
| A **default legend** exists for the subproduct | `analysis.product_legend` (`default_legend = TRUE`) |

The `mobile_app` column doubles as the "expose via web services" switch — the
same gate is used by the mobile-app collection APIs and STAC links.

### 4.1 Check which products are currently enabled

```bash
docker exec web python -c "
from database import querydb
for p in querydb.get_products_webservices():
    print(p.productcode, p.version, p.subproductcode)
"
```

Each line corresponds to an exposed layer whose WMS/WCS identifier is:

```
layer_<productcode>_<version>_<subproductcode>
```

For example `chirps-dekad` / `2.0` / `10d` →
`layer_chirps-dekad_2.0_10d`.

### 4.2 If a product is missing

Work through the four conditions above:

- **Activate the parent product** — via the Data Management / Product
  configuration UI, or by setting the product's `activated` flag.
- **Ensure the subproduct is not masked** and has `mobile_app = 't'`.
- **Create a default legend** for the subproduct in the Analysis / legend
  configuration — without it the layer is rejected even if everything else is
  correct.

After changing product/legend configuration, the next `GetCapabilities` call
reflects it (no container restart needed — only `OWS_ONLINE_URL` changes require
a restart).

---

## 5. Verifying the service

Run these checks after configuration. They can be run from inside the container
(as shown) or from any client that can reach the server.

### 5.1 Confirm the environment variable is set

```bash
docker exec web printenv OWS_ONLINE_URL
```

Expected: your configured URL (not blank, not the JRC default unless this *is*
the JRC server).

### 5.2 Confirm Capabilities advertises the correct URL

```bash
docker exec web sh -c "curl -s \
  'http://localhost:8080/webservices?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetCapabilities' \
  | grep -o 'OnlineResource[^>]*xlink:href=\"[^\"]*\"' | head -3"
```

Expected: the `xlink:href` values contain your `OWS_ONLINE_URL` host, **not**
`estation.jrc.ec.europa.eu` (unless this is the JRC server).

### 5.3 WMS GetMap (renders the most recent date if `DATE` is omitted)

```bash
docker exec web sh -c "curl -s -o /tmp/m.png -w '%{http_code} %{content_type}\n' \
 'http://localhost:8080/webservices?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=layer_chirps-dekad_2.0_10d&CRS=EPSG:4326&BBOX=-40,-20,40,60&WIDTH=800&HEIGHT=800&FORMAT=image/png'"
```

Expected: `200 image/png`. Replace the `LAYERS` value with one from Section 4.1.

### 5.4 WMS GetLegendGraphic

```bash
docker exec web sh -c "curl -s -o /tmp/l.png -w '%{http_code}\n' \
 'http://localhost:8080/webservices?SERVICE=WMS&REQUEST=GetLegendGraphic&LAYERS=layer_chirps-dekad_2.0_10d&FORMAT=image/png'"
```

Expected: `200`.

### 5.5 WCS GetCoverage (GeoTIFF)

```bash
docker exec web sh -c "curl -s -o /tmp/c.tif -w '%{http_code} %{content_type}\n' \
 'http://localhost:8080/webservices?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage&COVERAGEID=layer_chirps-dekad_2.0_10d'"
```

Expected: `200 image/tiff`. The returned GeoTIFF carries the product's scale
factor, offset, and nodata.

---

## 6. Using the services from a client

Give external users the **Capabilities URL**:

- WMS: `<OWS_ONLINE_URL>?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetCapabilities`
- WCS: `<OWS_ONLINE_URL>?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCapabilities`

Example (QGIS → Layer → Add Layer → Add WMS/WMTS Layer → New connection):

```
URL: http://my-host.example.org:8080/webservices
```

QGIS reads the layer list from Capabilities and then issues `GetMap`/`GetCoverage`
requests to the advertised OnlineResource — which is why Section 2 matters: if
the OnlineResource is wrong, the layers list but the tiles never load.

Request a specific date with the `DATE=YYYYMMDD` parameter (WMS) — if omitted the
service serves the most recent available date for the layer.

---

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Capabilities loads but maps/coverages fail in the client | `OWS_ONLINE_URL` wrong or unset → OnlineResource points elsewhere (often the JRC default) | Set `OWS_ONLINE_URL` to this machine's public `/webservices` URL (Section 2), restart the application, re-verify (Section 5.2) |
| OnlineResource shows `estation.jrc.ec.europa.eu` on a non-JRC host | `OWS_ONLINE_URL` is empty → hardcoded JRC fallback | Same as above |
| Change to `.env` has no effect | Running container keeps its startup environment | Restart the application: `./cs_install.sh down && ./cs_install.sh up` |
| `OWS_ONLINE_URL` set but clients still can't reach it | Value uses `localhost` or an internal name/port not reachable externally | Use the externally resolvable host/port (and `https` if behind a proxy) |
| Layer missing from `GetCapabilities` | Product not enabled | Check the four conditions in Section 4 (`activated`, not masked, `mobile_app='t'`, default legend) |
| `LayerNotDefined` exception on GetMap/GetCoverage | `LAYERS`/`COVERAGEID` does not exactly match `layer_<prod>_<ver>_<sprod>`, or product not enabled | Use an identifier from Section 4.1; verify enablement |
| Blank image or wrong (old) date | No `DATE` supplied → most-recent date served | Pass `DATE=YYYYMMDD` (or `TIME=`) explicitly |
| Wrong colours / everything one colour | Legend steps or scale mismatch vs the data encoding | Review the product's default legend and scale factor/offset |
| WCS GeoTIFF has wrong scale/nodata | Post-processing step that injects scale/offset/nodata did not run | Confirm the response is `image/tiff`; check WCS error log |

### 7.1 Log files

```bash
docker exec web tail -30 /data/static_data/log/mapserver_wms_layer_errors.log
docker exec web tail -30 /data/static_data/log/mapserver_wcs_layer_errors.log
```

---

## 8. Reference

### 8.1 Setting

| Setting | File | Default | Purpose |
|---------|------|---------|---------|
| `OWS_ONLINE_URL` | `<climatestation_dir>/.env` | `https://estation.jrc.ec.europa.eu/eStation3/webservices` | OnlineResource URL advertised in WMS/WCS GetCapabilities |

### 8.2 Endpoint and identifiers

- Endpoint: `/webservices`
- Layer / coverage id: `layer_<productcode>_<version>_<subproductcode>`
- WCS default version: `2.0.1` (1.0.0 and 1.1.1 also supported)

### 8.3 Configuration

- `OWS_ONLINE_URL` is set in `.env`; the `web` service loads it via
  `env_file: ./.env` in `docker-compose.yml`.
