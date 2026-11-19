/*

Q3.
Load the dimensions and the fact from the bronze_* tables, assigning the surrogate keys. 
Build a DimDate with a yyyymmdd integer DateKey. 
Populate the fact by joining bookings to the dimensions on their business keys. 
Acceptance criteria: dimensions and fact are populated; the fact row count matches bronze_bookings; every fact row resolves to all of its dimensions.

*/

USE VayuAir;
GO

-- ---------- 1. dim_aircrafts ----------
INSERT INTO dw.dim_aircrafts (aircraft_code, model, manufacturer, seat_capacity)
SELECT aircraft_code, model, manufacturer, seat_capacity
FROM dbo.bronze_aircraft;

-- ---------- 2. dim_airports ----------
INSERT INTO dw.dim_airports (airport_code, airport_name, city, country, region)
SELECT airport_code, airport_name, city, country, region
FROM dbo.bronze_airports;

-- ---------- 3. dim_passengers ----------
INSERT INTO dw.dim_passengers (passenger_id, passenger_name, home_airport_code, frequent_flyer_tier, signup_date)
SELECT passenger_id, passenger_name, home_airport_code, frequent_flyer_tier, signup_date
FROM dbo.bronze_passengers;

-- ---------- 4. dim_flights ----------
INSERT INTO dw.dim_flights (flight_id, flight_number, flight_date)
SELECT flight_id, flight_number, flight_date
FROM dbo.bronze_flights;

-- ---------- 5. dim_dates (one row per day, min to max date in the data) ----------
WITH bounds AS (
    SELECT MIN(d) AS start_date, MAX(d) AS end_date
    FROM (
        SELECT booking_date AS d FROM dbo.bronze_bookings
        UNION ALL SELECT travel_date as t FROM dbo.bronze_bookings
        UNION ALL SELECT flight_date as f FROM dbo.bronze_flights
    ) x
),
calendar AS (                                   -- recursive CTE (Session 2)
    SELECT start_date AS d FROM bounds
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM calendar
    WHERE d < (SELECT end_date FROM bounds)
    
)


INSERT INTO dw.dim_dates (date_key, calendar_date, [year], [quarter], [month], month_name, [day], day_name)
SELECT
    YEAR(d)*10000 + MONTH(d)*100 + DAY(d),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    MONTH(d),
    DATENAME(MONTH, d),
    DAY(d),
    DATENAME(WEEKDAY, d)
FROM calendar
OPTION (MAXRECURSION 0)
;


--SELECT COUNT(*), MIN(calendar_date), MAX(calendar_date) FROM dw.dim_dates;
--EXEC sp_rename 'dw.dim_dates.full_date', 'calendar_date', 'COLUMN';

-- ---------- 6. fact_ticket_sales ----------
INSERT INTO dw.fact_ticket_sales (
    booking_id, booking_date_key, travel_date_key, passenger_key, flight_key,
    origin_airport_key, dest_airport_key, aircraft_key,
    fare_class, booking_status, fare_amount, tax_amount, miles_earned)
SELECT
    b.booking_id,
    YEAR(b.booking_date)*10000 + MONTH(b.booking_date)*100 + DAY(b.booking_date),
    YEAR(b.travel_date)*10000  + MONTH(b.travel_date)*100  + DAY(b.travel_date),                                         -- travel date key, same formula
    p.passenger_key,
    fl.flight_key,
    o.airport_key,                               -- origin airport key
    d.airport_key,                               -- dest airport key
    ac.aircraft_key,
    b.fare_class, b.booking_status, b.fare_amount, b.tax_amount, b.miles_earned
FROM dbo.bronze_bookings b
JOIN dbo.bronze_flights   f  ON b.flight_id = f.flight_id      -- to get codes
JOIN dw.dim_passengers    p  ON b.passenger_id = p.passenger_id
JOIN dw.dim_flights       fl ON b.flight_id = fl.flight_id
JOIN dw.dim_airports      o  ON f.origin_airport_code = o.airport_code
JOIN dw.dim_airports      d  ON f.dest_airport_code   = d.airport_code
JOIN dw.dim_aircrafts     ac ON f.aircraft_code       = ac.aircraft_code
;


-- ---------- 7. CHECKS ----------
-- a) Row counts: fact must equal bronze_bookings (40,000)
SELECT 
(SELECT COUNT(*) FROM dbo.bronze_bookings)   AS bronze_rows,
(SELECT COUNT(*) FROM dw.fact_ticket_sales)  AS fact_rows;