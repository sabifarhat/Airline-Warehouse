/*

Q5.
Rebuild the passenger dimension as Slowly Changing Dimension Type 2 (a new
surrogate key per version, the stable business key, is_current, effective_from, effective_to). 
Apply stg_passenger_updates so that a changed tier or home airport expires the old version and opens a new one, and brand-new passengers are inserted.
Acceptance criteria: the two-step expire-then-insert pattern is used; 
a passenger who changed shows two versions with correct is_current and effective dates; new passengers appear as a single current row.

*/

USE VayuAir;
GO

-- Add three cols to passengers table

ALTER TABLE dw.dim_passengers
ADD is_current     BIT,
    effective_from DATE,
    effective_to   DATE NULL;
GO


-- Existing rows = the first version of each passenger
UPDATE dw.dim_passengers
SET is_current     = 1,
    effective_from = signup_date,   -- the version started when they joined
    effective_to   = NULL;


    
SELECT TOP 5 * FROM dw.dim_passengers;

-- Applying SCD type 2 

SELECT * FROM dw.dim_passengers;

SELECT * FROM dbo.stg_passenger_updates;

MERGE INTO dw.dim_passengers as tgt
USING dbo.stg_passenger_updates AS src
	ON tgt.passenger_id = src.passenger_id 
    AND tgt.is_current = 1
    
WHEN MATCHED AND ( tgt.home_airport_code <> src.home_airport_code
             OR tgt.frequent_flyer_tier <> src.frequent_flyer_tier ) THEN
             UPDATE SET tgt.is_current   = 0,
               tgt.effective_to = CAST(GETDATE() AS DATE)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (passenger_id, passenger_name, home_airport_code, frequent_flyer_tier, signup_date, is_current, effective_from, effective_to)
    VALUES (
        src.passenger_id, src.passenger_name, src.home_airport_code, src.frequent_flyer_tier, 
        NULL, 
        1, CAST(GETDATE() AS DATE), NULL
    );
GO

-- Insert the updated record

INSERT INTO dw.dim_passengers
    (passenger_id, passenger_name, home_airport_code, frequent_flyer_tier,
     signup_date, is_current, effective_from, effective_to)
SELECT
    src.passenger_id, src.passenger_name, src.home_airport_code, src.frequent_flyer_tier,
    expired.signup_date,                         -- keep the original signup date
    1, CAST(GETDATE() AS DATE), NULL
FROM dbo.stg_passenger_updates src
JOIN dw.dim_passengers expired
       ON expired.passenger_id = src.passenger_id
      AND expired.is_current   = 0
      AND expired.effective_to = CAST(GETDATE() AS DATE)
WHERE NOT EXISTS (
    SELECT 1 FROM dw.dim_passengers cur
    WHERE cur.passenger_id = src.passenger_id AND cur.is_current = 1
);
GO


-- Verification by checking count of the records updated

-- 1. Summary: total rows, current rows, expired rows
SELECT
    COUNT(*)                                         AS total_rows,
    SUM(CASE WHEN is_current = 1 THEN 1 ELSE 0 END)  AS current_rows,
    SUM(CASE WHEN is_current = 0 THEN 1 ELSE 0 END)  AS expired_rows
FROM dw.dim_passengers;

-- 2. Changed passengers: should show 2 versions each (1 expired + 1 current)
SELECT TOP 5 passenger_id, COUNT(*) AS versions
FROM dw.dim_passengers
GROUP BY passenger_id
HAVING COUNT(*) > 1;

-- 3. Full history of one changed passenger (paste an id from query 2)
SELECT passenger_key, passenger_id, passenger_name, home_airport_code,
       frequent_flyer_tier, is_current, effective_from, effective_to
FROM dw.dim_passengers
WHERE passenger_id = 700000           -- e.g. an id from query 2
ORDER BY effective_from;

-- 4. New passengers (in staging, not in bronze): should be 1 current row each
SELECT d.passenger_id, COUNT(*) AS versions, MAX(CAST(d.is_current AS INT)) AS is_current
FROM dw.dim_passengers d
WHERE d.passenger_id NOT IN (SELECT passenger_id FROM dbo.bronze_passengers)
GROUP BY d.passenger_id;

-- 5. Safety check: nobody has more than one current row (expect 0 rows)
SELECT passenger_id, COUNT(*) AS current_versions
FROM dw.dim_passengers
WHERE is_current = 1
GROUP BY passenger_id
HAVING COUNT(*) > 1;



/* =====================================================================
   Q5 - APPROACH, RESULT AND VERIFICATION
   =====================================================================
   --> WHY SCD TYPE 2
   - Passengers change tier or home airport over time. Overwriting would
     show old bookings under the new values. Type 2 keeps each version,
     so every booking stays linked to what was true at the time.

   --> APPROACH
   - Added is_current, effective_from and effective_to to the original table. Existing rows
     became the first version.
   - Step 1 (MERGE): tier or airport changed -> close the old row.
     New passenger -> insert as current.
   - Step 2 (INSERT): add the new current row for each closed passenger,
     keeping the original signup_date.
   - Two steps are needed because MERGE can do only one action per row.
   - Each version gets a new passenger_key; passenger_id stays the same.

   --> RESULT
   - 200 passengers changed, 50 new.
   - 1,750 rows in total: 1,550 current, 200 expired.

   --> VERIFICATION
   - Changed passengers have 2 versions; new passengers have 1.
   - No passenger has more than one current row.
   - New passengers have no signup_date (not in the staging feed).
   ===================================================================== */