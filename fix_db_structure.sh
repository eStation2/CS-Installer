#!/usr/bin/env sh

readonly LOGFILE="/var/log/climatestation/fix_db_structure.log"
readonly ERRFILE="/var/log/climatestation/fix_db_structure.err"

psql -h localhost -U estation -d estationdb -w > $LOGFILE 2> $ERRFILE <<'EOF'
  SET statement_timeout = 0;
  SET lock_timeout = 0;
  SET client_encoding = 'UTF8';
  SET standard_conforming_strings = on;
  SET check_function_bodies = false;
  SET client_min_messages = warning;


  CREATE TABLE IF NOT EXISTS climsoft.station (
    stationId varchar(255) NOT NULL,
    stationName varchar(255) DEFAULT NULL,
    wmoid varchar(20) DEFAULT NULL,
    icaoid varchar(20) DEFAULT NULL,
    wsi varchar(255) DEFAULT NULL,
    latitude decimal(11,6) DEFAULT NULL,
    qualifier varchar(20) DEFAULT NULL,
    longitude decimal(11,6) DEFAULT NULL,
    elevation varchar(255) DEFAULT NULL,
    geoLocationMethod varchar(255) DEFAULT NULL,
    geoLocationAccuracy decimal(11,6) DEFAULT NULL,
    openingDatetime varchar(50) DEFAULT NULL,
    closingDatetime varchar(50) DEFAULT NULL,
    country varchar(50) DEFAULT NULL,
    authority varchar(255) DEFAULT NULL,
    adminRegion varchar(255) DEFAULT NULL,
    drainageBasin varchar(255) DEFAULT NULL,
    wacaSelection smallint DEFAULT '0',
    cptSelection smallint DEFAULT '0',
    stationOperational smallint DEFAULT '0',
    gtsWSI smallint DEFAULT '0',
    geom geometry(Point, 4326),
    CONSTRAINT station_pk PRIMARY KEY (stationId)
  )
  WITH (
    OIDS=FALSE
  );
  ALTER TABLE climsoft.station
    OWNER TO estation;

  -- Create the insert trigger
  CREATE OR REPLACE FUNCTION climsoft.station_insert_trigger()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.geom := ST_SetSRID(ST_MakePoint(CAST(NEW.longitude AS FLOAT), CAST(NEW.latitude AS FLOAT)), 4326);
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  DROP TRIGGER IF EXISTS insert_station_trigger ON climsoft.station;
  CREATE TRIGGER insert_station_trigger
  BEFORE INSERT ON climsoft.station
  FOR EACH ROW
  EXECUTE FUNCTION climsoft.station_insert_trigger();

  -- Create the update trigger
  CREATE OR REPLACE FUNCTION climsoft.station_update_trigger()
  RETURNS TRIGGER AS $$
  BEGIN
    NEW.geom := ST_SetSRID(ST_MakePoint(CAST(NEW.longitude AS FLOAT), CAST(NEW.latitude AS FLOAT)), 4326);
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  DROP TRIGGER IF EXISTS update_station_trigger ON climsoft.station;
  CREATE TRIGGER update_station_trigger
  BEFORE UPDATE ON climsoft.station
  FOR EACH ROW
  EXECUTE FUNCTION climsoft.station_update_trigger();

  -- ALTER TABLE climsoft.obselement
  --    ADD COLUMN IF NOT EXISTS temporal_aggregation character varying;

  CREATE TABLE IF NOT EXISTS climsoft.obselement (
    elementId bigint NOT NULL DEFAULT '0',
    abbreviation varchar(255) DEFAULT NULL,
    elementName varchar(255) DEFAULT NULL,
    description varchar(255) DEFAULT NULL,
    elementScale decimal(8,2) DEFAULT NULL,
    upperLimit varchar(255) DEFAULT NULL,
    lowerLimit varchar(255) DEFAULT NULL,
    units varchar(255) DEFAULT NULL,
    elementtype varchar(50) DEFAULT NULL,
    qcTotalRequired integer DEFAULT '0',
    selected smallint DEFAULT '0',
    temporal_aggregation character varying COLLATE pg_catalog."default",
    CONSTRAINT obselement_pk PRIMARY KEY (elementId)
  )
  WITH (
    OIDS=FALSE
  );
  ALTER TABLE climsoft.obselement
    OWNER TO estation;

  -- Create the insert trigger
  CREATE OR REPLACE FUNCTION climsoft.obselement_insert_trigger()
  RETURNS TRIGGER AS $$
  DECLARE
      result_string VARCHAR;
  BEGIN
      -- Convert the input string to lowercase
      result_string := LOWER(NEW.elementtype);
      -- Remove the carriage return (\r) character
      result_string := REPLACE(result_string, E'\\r', '');

      IF result_string = 'hourly' THEN
          NEW.elementtype := 'e1hour';
      ELSIF result_string = 'daily' THEN
          NEW.elementtype := 'e1day';
      ELSIF result_string = 'monthly' THEN
          NEW.elementtype := 'e1month';
      ELSIF result_string = 'decadal' THEN
          NEW.elementtype := 'e1dekad';
      ELSIF result_string = 'AWS' THEN
          NEW.elementtype := 'undefined';
      ELSE
          NEW.elementtype := 'undefined';
      END IF;

    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  DROP TRIGGER IF EXISTS insert_obselement_trigger ON climsoft.obselement;
  CREATE TRIGGER insert_obselement_trigger
  BEFORE INSERT ON climsoft.obselement
  FOR EACH ROW
  EXECUTE FUNCTION climsoft.obselement_insert_trigger();

  -- Create the update trigger
  CREATE OR REPLACE FUNCTION climsoft.obselement_update_trigger()
  RETURNS TRIGGER AS $$
  DECLARE
      result_string VARCHAR;
  BEGIN
      -- Convert the input string to lowercase
      result_string := LOWER(NEW.elementtype);
      -- Remove the carriage return (\r) character
      result_string := REPLACE(result_string, E'\\r', '');

      IF result_string = 'hourly' THEN
          NEW.elementtype := 'e1hour';
      ELSIF result_string = 'daily' THEN
          NEW.elementtype := 'e1day';
      ELSIF result_string = 'monthly' THEN
          NEW.elementtype := 'e1month';
      ELSIF result_string = 'decadal' THEN
          NEW.elementtype := 'e1dekad';
      ELSIF result_string = 'AWS' THEN
          NEW.elementtype := 'undefined';
      ELSE
          NEW.elementtype := 'undefined';
      END IF;

      RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  DROP TRIGGER IF EXISTS update_obselement_trigger ON climsoft.obselement;
  CREATE TRIGGER update_obselement_trigger
  BEFORE UPDATE ON climsoft.obselement
  FOR EACH ROW
  EXECUTE FUNCTION climsoft.obselement_update_trigger();


  CREATE TABLE IF NOT EXISTS climsoft.observationfinal
  (
    recordedFrom varchar(255) NOT NULL,
    describedBy bigint DEFAULT NULL,
    obsDatetime date DEFAULT NULL,
    obsLevel varchar(255) DEFAULT 'surface',
    obsValue decimal(8,2) DEFAULT NULL,
    flag varchar(255) DEFAULT 'N',
    period integer DEFAULT NULL,
    qcStatus integer DEFAULT '0',
    qcTypeLog text,
    acquisitionType integer DEFAULT '0',
    dataForm varchar(255) DEFAULT NULL,
    capturedBy varchar(255) DEFAULT NULL,
    mark smallint DEFAULT NULL,
    temperatureUnits varchar(255) DEFAULT NULL,
    precipitationUnits varchar(255) DEFAULT NULL,
    cloudHeightUnits varchar(255) DEFAULT NULL,
    visUnits varchar(255) DEFAULT NULL,
    dataSourceTimeZone integer DEFAULT '0',

    CONSTRAINT observationfinal_pk PRIMARY KEY (recordedFrom,describedBy,obsDatetime,obsLevel),
    CONSTRAINT obselement_observationFinal_fk FOREIGN KEY (describedBy)
        REFERENCES climsoft.obselement (elementId) MATCH SIMPLE
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT station_observationFinal_fk FOREIGN KEY (recordedFrom)
        REFERENCES climsoft.station (stationId) MATCH SIMPLE
        ON UPDATE CASCADE ON DELETE SET NULL
  )
  WITH (
    OIDS=FALSE
  );
  ALTER TABLE climsoft.observationfinal
    OWNER TO estation;

  ALTER TABLE climsoft.observationfinal
      ALTER COLUMN obsdatetime TYPE timestamp(4) without time zone ;

  ALTER TABLE climsoft.observationfinal
      ALTER COLUMN obsvalue TYPE numeric (12, 2);

  DELETE FROM analysis.user_workspaces WHERE userid = 'jrc_ref';

  DELETE FROM analysis.user_graph_templates WHERE workspaceid not in (SELECT workspaceid FROM analysis.user_workspaces);

  DELETE FROM analysis.user_graph_tpl_drawproperties WHERE graph_tpl_id not in (SELECT graph_tpl_id FROM analysis.user_graph_templates);

  DELETE FROM analysis.user_graph_tpl_timeseries_drawproperties WHERE graph_tpl_id not in (SELECT graph_tpl_id FROM analysis.user_graph_templates);

  DELETE FROM analysis.user_graph_tpl_yaxes WHERE graph_tpl_id not in (SELECT graph_tpl_id FROM analysis.user_graph_templates);

  DELETE FROM analysis.user_map_templates WHERE workspaceid not in (SELECT workspaceid FROM analysis.user_workspaces);


EOF
    
