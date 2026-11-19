/* 
   Q4 - SNOWFLAKE THE GEOGRAPHY
   
   Normalise the airport dimension into three linked tables: airport,
   city, and country. Load them, and write one sentence on the trade-off
   you are making.
   Acceptance criteria: three linked tables with foreign keys; a query can
   resolve an airport all the way up to its country.
  
  */

USE VayuAir; 
GO


-- 1. Tables: country -> city -> airport
CREATE TABLE dw.dim_countries (
    country_key  INT IDENTITY(1,1) PRIMARY KEY,
    country_name VARCHAR(50) NOT NULL,
    region       VARCHAR(50)
);

CREATE TABLE dw.dim_cities (
    city_key    INT IDENTITY(1,1) PRIMARY KEY,
    city_name   VARCHAR(50) NOT NULL,
    country_key INT NOT NULL REFERENCES dw.dim_countries(country_key)
);

CREATE TABLE dw.dim_airports_sf (                 -- sf = snowflaked
    airport_key  INT IDENTITY(1,1) PRIMARY KEY,
    airport_code CHAR(3) NOT NULL,                -- business key
    airport_name VARCHAR(100),
    city_key     INT NOT NULL REFERENCES dw.dim_cities(city_key)
);

-- 2. Load in order
INSERT INTO dw.dim_countries (country_name, region)
SELECT DISTINCT country, region
FROM dbo.bronze_airports;

INSERT INTO dw.dim_cities (city_name, country_key)
SELECT DISTINCT a.city, c.country_key
FROM dbo.bronze_airports a
JOIN dw.dim_countries c ON a.country = c.country_name;

INSERT INTO dw.dim_airports_sf (airport_code, airport_name, city_key)
SELECT a.airport_code, a.airport_name, ci.city_key
FROM dbo.bronze_airports a
JOIN dw.dim_countries c  ON a.country = c.country_name
JOIN dw.dim_cities    ci ON a.city = ci.city_name AND ci.country_key = c.country_key;


-- 3. Resolve airport all the way up to country
SELECT ap.airport_code, ap.airport_name, ci.city_name, co.country_name, co.region
FROM dw.dim_airports_sf ap
JOIN dw.dim_cities    ci ON ap.city_key    = ci.city_key
JOIN dw.dim_countries co ON ci.country_key = co.country_key
ORDER BY co.country_name, ci.city_name;


-- 4. Verification
SELECT
    (SELECT COUNT(*) FROM dbo.bronze_airports) AS bronze_airports,
    (SELECT COUNT(*) FROM dw.dim_airports_sf)  AS airports_sf,
    (SELECT COUNT(*) FROM dw.dim_cities)       AS cities,
    (SELECT COUNT(*) FROM dw.dim_countries)    AS countries;

/* =====================================================================
   Q4 - APPROACH, RESULT AND VERIFICATION
   =====================================================================
   --> APPROACH
   - bronze_airports repeats city, country and region on every airport
     row. It was split into three linked tables:
       dim_airports_sf -> dim_cities -> dim_countries
   - Each table has an IDENTITY surrogate key. Each airport points to its
     city (city_key), and each city points to its country (country_key).
   - Region is kept as a column in dim_countries, because it describes the
     country. A separate region table was not needed.
   - Loaded in order (country, then city, then airport) so every foreign
     key has a row to point to. DISTINCT stores each country and city once.
   - The city lookup also matches the country, so two cities with the same
     name in different countries stay separate.
   - The original dim_airports (star version) is kept unchanged, because
     fact_ticket_sales points to it.

   --> RESULT
   - The resolve query returns every airport with its city, country and
     region, e.g. DEL -> Delhi -> India -> South Asia.

   --> VERIFICATION
   - airports_sf = bronze_airports (24 rows), so no airport was lost.
   - Every airport resolves to a city and a country through inner joins.

   --> TRADE-OFF
   - Snowflaking stores each country and city only once (less repetition,
     easier updates), but reaching an airport's country now needs two
     extra joins, which makes queries longer and slightly slower.
   ===================================================================== */