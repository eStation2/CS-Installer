Release Note for ClimSA Station version 1.4.0

This Note describes the main modifications contained in version 1.4.0, with respect to the features (Section 1), the datasets treated on the system (Section 2) and the bug fixing changes (Section 3).

# FEATURES

## SystemTechnology Stack

- The PostgreSQL database has been migrated from version 12.1 to version 17.6.
- Python version is upgraded from version 3.8.5 to version 3.12.3
- Upgraded Javascript libraries:
  - OpenLayers version 10.5.0 (from version 6.15.1)
  - HighCharts is removed and replaced by Apache eCharts version 5.6.0
  - Html2canvas version 1.4.1 (from version 0.5.0).

## General Features

- In the Analysis Tool Highcharts library is changed to Apache eCharts, so some graphical properties might be slightly different from the old view.
- The timeline of the Mapviewer where you select the dates of the product is with new look and feel, because of the change to Apache eCharts.
- The default zoom in the Analysis map view is now linked to the coverage of the product and doesn't view Africa by default.
- Now it is possible to remove the empty folders from the Data Management page.

## Documentation

- The following documents have been updated to 1.4.0 version in the current release:
  - Product report
  - Data Provider registration manual
- The new historical archive's location <https://europa.eu/!WQt4WV>

# Products

Some new products are added and also the existing products are modified

- fPAR (Fraction of Photosynthetically Active Radiation) from MARS @ 500m and it is a key biophysical variable for vegetation productivity estimation
- FAPAR (Fraction of Absorbed Photosynthetically Active Radiation) from Global Drought Observatory @ 10km used to assess the greenness and health of vegetation
- The Copernicus Marine services physical model data includes daily files of temperature, salinity, sea level height anomaly, mixed layer depth from the top to the bottom over the global ocean with a 1/12 degree horizontal resolution.
  - These model data along with chlorophyll-a and its gradient are used to compute the feeding habitat of various fish species in the Jupyter notebook.
- The new version of Soil Water Index V4.0 which quantifies the moisture condition in the soil.
- The Copernicus Land Monitoring Products datasources are changed to Copernicus Data Space Ecosystem(CDSE), the users of these products are requested to create the credentials and set on the Portfolio page following the Data Provider registration manual in the Help page.

# BUG FIXING

Several bugs were identified by JRC or indicated by the Users during the training and workshops. These activities are reported for completeness's sake and for traceability, though they are not of primary interest for the Users (more for JRC internal reference).

- The legend is displayed while downloading the map as PNG.
- Legend visualization on the Matrix graphs are adjusted.

**NOTE on versioning**

The Climate stations define 3 distinct versions, as below

Software Version: 1.4.0 (is the main version, visible in the header of every page)

Database Version: 142 (PostgreSQL DB version, as displayed in the System page)

Configuration Version: 1.1.3 (internal only)

IMPACT: 5.127b