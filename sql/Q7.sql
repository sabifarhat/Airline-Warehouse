
/* 

(a) Map every table in this pipeline to a medallion layer (bronze, silver, or gold) and say in a line why each sits where. 
(b) Write a data contract for the bronze_bookings feed. 
Acceptance criteria: every table is assigned a layer with a short reason; 
the contract states the schema and types, the allowed values for fare_class and booking_status, a freshness or delivery SLA, the owner, 
and one example each of a breaking and a non-breaking change.


*/

-- (a)

-- Bronze: raw data, loaded as-is from the source
SELECT TOP 2 * FROM VayuAir.dbo.bronze_passengers
SELECT TOP 2 * FROM VayuAir.dbo.bronze_aircraft
SELECT TOP 2 * FROM VayuAir.dbo.bronze_airports
SELECT TOP 2 * FROM VayuAir.dbo.bronze_bookings
SELECT TOP 2 * FROM VayuAir.dbo.bronze_flights
SELECT TOP 2 * FROM VayuAir.dbo.stg_passenger_updates

-- ==================================================================================================
-- Silver: cleaned, conformed and history-tracked

-- After applying SCD Type 2 changes to bronze_passengers, we get dw.dim_passengers
-- VayuAir.dbo.bronze_passengers  -->  VayuAir.dw.dim_passengers

-- -------------------------------------------------------------------------------------------------
-- Normalised (snowflaked) the airports table into airports, cities and countries.
-- dw.dim_airports_sf has city_key, which links to dw.dim_cities; dw.dim_cities has
-- country_key, which links to dw.dim_countries.
-- VayuAir.dbo.bronze_airports  -->  VayuAir.dw.dim_airports_sf, VayuAir.dw.dim_cities, VayuAir.dw.dim_countries

-- ==================================================================================================
-- Gold: star schema that dashboards query

-- VayuAir.dw.dim_aircrafts
-- VayuAir.dw.dim_airports       --> Star version with an IDENTITY surrogate key; the fact links to this,
--                                   not to the snowflaked dw.dim_airports_sf
-- VayuAir.dw.dim_flights
-- VayuAir.dw.dim_dates          --> Created to join on booking and travel dates for time-based analysis
-- VayuAir.dw.fact_ticket_sales  --> Partitioned by travel month


-- (b) Contract
/*

Purpose: daily feed of ticket bookings from the Vayu Air booking system.
It's the source of fact_ticket_sales.

### 1. Schema and types


| Column |                 | Type  |                      | Rules |
-------------------------------------------------------------------------------------------------------------------
booking_id                  - INT                         [Required, unique per row]
passenger_id                - INT                         [Required, must exist in bronze_passengers]
flight_id                   - INT                         [Required, must exist in bronze_flights]
booking_date                - DATE                        [Required]
travel_date                 - DATE                        [Required, on or after booking_date]
fare_class                  - VARCHAR(20)                 [Required; Economy / Premium Economy / Business / First]
fare_amount                 - DECIMAL(10,2)               [Required, 0 or more, in INR]
tax_amount                  - DECIMAL(10,2)               [Required, 0 or more, in INR]
booking_status              - VARCHAR(20)                 [Required; Confirmed / Cancelled / NoShow]
miles_earned                - INT                         [Required, 0 or more; can exceed 32,767, so INT not SMALLINT]


### 2. Allowed values
- fare_class: Economy, Premium Economy, Business, First
- booking_status: Confirmed, Cancelled, NoShow
- Only 'Confirmed' bookings count as revenue.

### 3. Freshness / delivery SLA
- Delivered **once a day by 06:00**, containing all bookings created or changed
  the previous day.
- If the feed is more than **2 hours late**, the data team is alerted and
  dashboards show the last successful load date.

### 4. Ownership
- Producer (feed owner): Booking System platform team
- Warehouse platform (SQL data warehouse and cloud): Enterprise Data Engineering team
- Consumer: Analytics Engineering team (lead: Neha)
- Issues in the feed are fixed by the producer. Issues in the warehouse
  load are fixed by Enterprise Data Engineerin

### 5. Changes to the contract
- Any change is announced **at least 3 weeks in advance** and the contract
  version is updated.
- Non-breaking change (example): adding a new **optional** column, such as
  `booking_channel` (web / app / agent). Existing loads keep working.
- Breaking change (example): renaming `fare_amount` to `base_fare`, or
  removing a column. The warehouse load would fail or load wrong data, so this
  needs a new contract version and a coordinated release.
- Adding a new allowed value (e.g. a `Refunded` booking_status) is also treated
  as breaking, because revenue logic depends on the status list.

*/