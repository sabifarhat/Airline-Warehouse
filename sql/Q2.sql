/* 

Q2.
Create a dw schema and write the star schema DDL: 
a central FactTicketSales at your declared grain plus the dimensions it needs (date, passenger, flight, airport, aircraft). 
Use surrogate keys on the dimensions and foreign keys on the fact, and keep only additive measures on the fact. 
Acceptance criteria: fact at the declared grain with surrogate-key foreign keys; each dimension has a surrogate primary key and keeps its business key.

*/

USE VayuAir;
Go
CREATE SCHEMA dw;
GO


CREATE TABLE dw.dim_flights
(
flight_key INT IDENTITY(1,1) PRIMARY KEY, -- Surrogate Key
flight_id INT NOT NULL,                   -- Business Key
flight_number       VARCHAR(10),
flight_date         DATE
)
;

CREATE TABLE dw.dim_aircrafts
(
aircraft_key INT IDENTITY(1,1) PRIMARY KEY, -- Surrogate Key
aircraft_code VARCHAR(10) NOT NULL,         -- Business Key
model         VARCHAR(50),
manufacturer  VARCHAR(50),  
seat_capacity INT 
)
;


CREATE TABLE dw.dim_airports
(
airport_key INT IDENTITY(1,1) PRIMARY KEY, -- Surrogate Key
airport_code CHAR(3) NOT NULL,         -- Business Key
airport_name VARCHAR(100),
city         VARCHAR(50),
country      VARCHAR(50),
region       VARCHAR(50)
)
;

CREATE TABLE dw.dim_passengers
(
passenger_key       INT IDENTITY(1,1) PRIMARY KEY,  -- Surrogate Key
passenger_id        INT NOT NULL,                   -- Business Key
passenger_name      VARCHAR(100),
home_airport_code   CHAR(3),
frequent_flyer_tier VARCHAR(20),                    
signup_date         DATE
);

CREATE TABLE dw.dim_dates
(
date_key   INT PRIMARY KEY,   -- key yyyymmdd, not identity method
full_date  DATE NOT NULL,
[year]     INT,
[quarter]  INT,
[month]    INT,
month_name VARCHAR(10),
[day]      INT,
day_name   VARCHAR(10)
);

CREATE TABLE dw.fact_ticket_sales
(
-- GRAIN: one row per booking (ticket): one passenger on one flight
booking_id         INT PRIMARY KEY,                                          -- Primary key to retain the logic of one row per booking
booking_date_key   INT NOT NULL REFERENCES dw.dim_dates(date_key),           
travel_date_key    INT NOT NULL REFERENCES dw.dim_dates(date_key),           
passenger_key      INT NOT NULL REFERENCES dw.dim_passengers(passenger_key),
flight_key         INT NOT NULL REFERENCES dw.dim_flights(flight_key),
origin_airport_key INT NOT NULL REFERENCES dw.dim_airports(airport_key),     
dest_airport_key   INT NOT NULL REFERENCES dw.dim_airports(airport_key),     
aircraft_key       INT NOT NULL REFERENCES dw.dim_aircrafts(aircraft_key),
fare_class         VARCHAR(20),												-- Descriptive attribute (no separate dim)
booking_status     VARCHAR(20),												-- Descriptive attribute (no separate dim)
fare_amount        DECIMAL(10,2),											-- Additive measure
tax_amount         DECIMAL(10,2),											-- Additive measure
miles_earned       INT														-- Additive measure
)
;


/*============================================================================================================================
 --> DESIGN APPROACH

   =====================================================================
   Q2 - STAR SCHEMA TABLES (dw schema)
   =====================================================================
   --> STAR SCHEMA
   - One main fact table, fact_ticket_sales (called FactTicketSales in the
     brief). One row = one booking (one passenger on one flight).
   - Five dimension tables around it: dim_dates, dim_passengers, dim_flights,
     dim_airports, dim_aircrafts.

   --> KEYS
   - Each dim table has its own number key (surrogate key), created
     automatically with IDENTITY. It also keeps the original ID from the
     source (business key), e.g. airport_code, passenger_id.
   - dim_dates uses the date itself as its ID, written as a number
     (e.g. 20250730), which is the usual way for date tables.
   - The fact table stores surrogate keys as foreign keys, not the source codes.
     If a code changes (e.g. DEL becomes DELH), only the dim table is
     updated; the fact table stays the same.
   - booking_id is the fact's primary key, so each booking can appear
     only once.

   --> DESIGN CHOICES
   - dim_dates is used twice (booking date and travel date), and
     dim_airports is used twice (origin and destination).
   - Airport and aircraft codes are not repeated in dim_flights, because
     the fact table already links to dim_airports and dim_aircrafts through surrogate keys.
     Each piece of information is stored in one place only.
   - dim_flights keeps only flight details (flight_number, flight_date).
   - fare_class and booking_status stay in the fact table as text,
     because they have only a few categorical values each.
   - The only measures stored on the fact are additive: fare_amount,
     tax_amount, miles_earned. Non-additive values (e.g. average fare,
     tax as a % of fare) are calculated in queries from these sums,
     not stored.

     =====================================================================

*/

