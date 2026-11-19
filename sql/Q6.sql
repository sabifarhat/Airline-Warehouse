/* 
   Q6 - PARTITION THE FACT BY DATE
   
   The sales fact is the biggest table in the warehouse. Partition it by
   date using a partition function and a partition scheme. Then run two
   queries: one that filters on the partition key, and one that filters
   on a non-partition column.
   Acceptance criteria: a partition function and scheme exist and the fact
   sits on the scheme; you show, using the actual execution plan, that the
   first query prunes to a small number of partitions and the second does
   not, and you explain why.
    */

USE VayuAir;
GO

-- ---------- 0. CHECK DATE RANGE ----------
SELECT MIN(travel_date_key) AS min_key,     -- 20250101
       MAX(travel_date_key) AS max_key      -- 20260331
FROM dw.fact_ticket_sales;

-- ---------- 1. BACK UP CURRENT FACT ROWS ----------
DROP TABLE IF EXISTS dw.fact_backup;
SELECT * INTO dw.fact_backup FROM dw.fact_ticket_sales;   -- plain copy, 40,000 rows
GO

-- ---------- 2. CLEAN UP (order: tables -> scheme -> function) ----------
DROP TABLE IF EXISTS dw.fact_ticket_sales_part;
DROP TABLE IF EXISTS dw.fact_ticket_sales;
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'ps_travel_month')
    DROP PARTITION SCHEME ps_travel_month;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'pf_travel_month')
    DROP PARTITION FUNCTION pf_travel_month;
GO

-- ---------- 3. PARTITION FUNCTION: 15 monthly partitions ----------
CREATE PARTITION FUNCTION pf_travel_month (INT)
AS RANGE RIGHT FOR VALUES (
    20250201, 20250301, 20250401, 20250501, 20250601, 20250701,
    20250801, 20250901, 20251001, 20251101, 20251201,
    20260101, 20260201, 20260301
);
GO

-- ---------- 4. PARTITION SCHEME: all partitions on PRIMARY ----------
CREATE PARTITION SCHEME ps_travel_month
AS PARTITION pf_travel_month ALL TO ([PRIMARY]);
GO

-- ---------- 5. FACT TABLE ON THE SCHEME ----------
CREATE TABLE dw.fact_ticket_sales
(
    booking_id         INT NOT NULL,
    booking_date_key   INT NOT NULL REFERENCES dw.dim_dates(date_key),
    travel_date_key    INT NOT NULL REFERENCES dw.dim_dates(date_key),
    passenger_key      INT NOT NULL REFERENCES dw.dim_passengers(passenger_key),
    flight_key         INT NOT NULL REFERENCES dw.dim_flights(flight_key),
    origin_airport_key INT NOT NULL REFERENCES dw.dim_airports(airport_key),
    dest_airport_key   INT NOT NULL REFERENCES dw.dim_airports(airport_key),
    aircraft_key       INT NOT NULL REFERENCES dw.dim_aircrafts(aircraft_key),
    fare_class         VARCHAR(20),
    booking_status     VARCHAR(20),
    fare_amount        DECIMAL(10,2),
    tax_amount         DECIMAL(10,2),
    miles_earned       INT,
    CONSTRAINT pk_fact_ticket_sales
        PRIMARY KEY (booking_id, travel_date_key)   -- must include the partition column
)
ON ps_travel_month (travel_date_key);              -- partition column
GO

-- ---------- 6. RELOAD FROM BACKUP ----------
INSERT INTO dw.fact_ticket_sales
SELECT * FROM dw.fact_backup;

SELECT COUNT(*) AS rows_loaded FROM dw.fact_ticket_sales;   -- expect 40,000

DROP TABLE dw.fact_backup;
GO

-- ---------- 7. CHECKS ----------
-- a) Rows per partition: expect 15 rows, one month each, total 40,000
SELECT
    $PARTITION.pf_travel_month(travel_date_key) AS partition_no,
    MIN(travel_date_key)                        AS from_key,
    MAX(travel_date_key)                        AS to_key,
    COUNT(*)                                    AS row_count
FROM dw.fact_ticket_sales
GROUP BY $PARTITION.pf_travel_month(travel_date_key)
ORDER BY partition_no;

-- b) Grain still holds: no booking_id appears twice (expect 0 rows)
SELECT booking_id, COUNT(*) AS cnt
FROM dw.fact_ticket_sales
GROUP BY booking_id
HAVING COUNT(*) > 1;

-- ---------- 8. TEST QUERIES (turn on Actual Execution Plan: Ctrl+M) ----------
-- Query A: filters on the partition column -> expect 1 partition read
SELECT SUM(fare_amount) AS june_revenue
FROM dw.fact_ticket_sales
WHERE travel_date_key BETWEEN 20250601 AND 20250630;

-- Query B: filters on a non-partition column -> expect all 15 partitions read
SELECT SUM(fare_amount) AS passenger_revenue
FROM dw.fact_ticket_sales
WHERE booking_date_key BETWEEN 20250601 AND 20250630;

   
/* 
   Q6 - APPROACH, RESULT AND VERIFICATION
  
   --> APPROACH
   - Partitioned the fact on travel_date_key (reports mostly filter by
     travel date): 15 monthly partitions, Jan 2025 - Mar 2026.
   - pf_travel_month (RANGE RIGHT, month starts) + ps_travel_month
     (all on PRIMARY). The fact was rebuilt ON the scheme and reloaded.
   - Primary key = (booking_id, travel_date_key): SQL Server requires the
     partition column in the key (booking_id alone gave error Msg 1908).
     The duplicate check confirms the grain is unchanged.

   --> RESULT (actual execution plan)
   - Query A (travel_date_key, June):  1 partition,  3,120 rows read
   - Query B (booking_date_key, June): 15 partitions, 40,000 rows read

   --> WHY
   - A filters on the partition column, so only June's partition is read
     (partition elimination).
   - B filters on booking date. Tickets booked in June can be for travel
     in any month, so every partition is read.
   - Partitioning helps only when queries filter on the partition column.

   --> VERIFICATION
   - 40,000 rows across 15 partitions; no duplicate booking_id.
   - Plan screenshots: /screenshots/Q6_queryA_plan.png, Q6_queryB_plan.png
    */
   
