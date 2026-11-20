# Airline Data Warehouse (Vayu Air)

A SQL Server data warehouse built from raw airline booking data. The project turns six raw source tables into a star schema, with a snowflaked geography, an SCD Type 2 passenger dimension, a date-partitioned fact table, medallion layers and a data contract.

**Tools:** SQL Server 2025, SSMS, T-SQL, Git

![Medallion architecture](screenshots/medallion_architecture.png)

---

## Data

| Source table | Rows | Description |
|---|---|---|
| bronze_airports | 24 | One row per airport (city, country, region repeated) |
| bronze_aircraft | 10 | One row per aircraft type |
| bronze_passengers | 1,500 | One row per passenger (current state) |
| bronze_flights | 2,000 | One row per flight |
| bronze_bookings | 40,000 | One row per ticket sold |
| stg_passenger_updates | 250 | Daily change feed (tier / home airport changes and new passengers) |

---

## Solution by question

| # | Topic | File |
|---|---|---|
| Q1 | Grain and column classification | [sql/Q1.sql](sql/Q1.sql) |
| Q2 | Star schema DDL | [sql/Q2.sql](sql/Q2.sql) |
| Q3 | Load dimensions and fact | [sql/Q3.sql](sql/Q3.sql) |
| Q4 | Snowflaked geography | [sql/Q4.sql](sql/Q4.sql) |
| Q5 | Passenger dimension as SCD Type 2 | [sql/Q5.sql](sql/Q5.sql) |
| Q6 | Date partitioning of the fact | [sql/Q6.sql](sql/Q6.sql) |
| Q7 | Medallion layers and data contract | [sql/Q7.sql](sql/Q7.sql) |

### Q1 - Grain
**One row per booking (ticket): one passenger on one flight.** `booking_id` is unique and stays on the fact as a degenerate dimension. Every column was classified as a dimension key, a descriptive attribute or a measure. `fare_amount`, `tax_amount` and `miles_earned` are additive; averages and percentages are non-additive and are calculated in queries, not stored.

### Q2 - Star schema
- Fact: `dw.fact_ticket_sales` (called FactTicketSales in the brief).
- Dimensions: `dim_dates`, `dim_passengers`, `dim_flights`, `dim_airports`, `dim_aircrafts`.
- Each dimension has an IDENTITY surrogate key and keeps its source business key. `dim_dates` uses a yyyymmdd integer key.
- The fact stores only surrogate keys and additive measures. `dim_dates` and `dim_airports` are role-playing dimensions (booking/travel date, origin/destination airport).
- Each piece of information is stored in one place: airport and aircraft codes are not repeated in `dim_flights`, because the fact links to those dimensions directly.

### Q3 - Load
Dimensions were loaded first, then the fact, by matching each booking's business keys to the dimensions and storing their surrogate keys. `dim_dates` was generated with a recursive CTE covering every date in the data.
**Checks:** fact rows = 40,000 (matches bronze_bookings); every fact row resolves to all of its dimensions.

### Q4 - Snowflaked geography
Airport was normalised into `dim_airports_sf -> dim_cities -> dim_countries` (region kept on country). A query resolves all 24 airports up to their country.
**Trade-off:** less repetition and easier updates, but two extra joins to reach country. The fact keeps using the star `dim_airports` for simpler, faster reporting; in production, only one design would be kept.

### Q5 - SCD Type 2
`dim_passengers` gained `is_current`, `effective_from` and `effective_to`. Using the two-step pattern (MERGE to expire changed rows and insert new passengers, then INSERT to open new versions):
- 200 passengers changed tier or home airport: each now has 2 versions.
- 50 new passengers: 1 current row each.
- 1,750 rows in total; no passenger has more than one current row.

### Q6 - Partitioning
The fact is partitioned by `travel_date_key` into 15 monthly partitions (Jan 2025 - Mar 2026), using a partition function (RANGE RIGHT) and scheme. The primary key became `(booking_id, travel_date_key)`, because SQL Server requires the partition column in the key.

| Query | Filter | Actual partition count | Rows read |
|---|---|---|---|
| A | travel_date_key (June 2025) | 1 | 3,120 |
| B | booking_date_key (June 2025) | 15 | 40,000 |

Query A filters on the partition column, so only June's partition is read (partition elimination). Query B filters on booking date, which can belong to any travel month, so every partition is read.

![Query A plan](screenshots/Q6_queryA_plan.png)
![Query B plan](screenshots/Q6_queryB_plan.png)

### Q7 - Medallion layers and data contract
- **Bronze:** the six raw source tables.
- **Silver:** `dim_passengers` (history-tracked) and the snowflaked geography tables.
- **Gold:** the partitioned star schema (`fact_ticket_sales`, `dim_dates`, `dim_flights`, `dim_airports`, `dim_aircrafts`).

The data contract for `bronze_bookings` defines the schema and types, the allowed values for `fare_class` and `booking_status`, a daily delivery SLA, ownership, and examples of breaking and non-breaking changes.

---

## Notes and limitations
- `booking_status` holds only the latest status; status history would need a transaction fact (one row per status change).
- New passengers have no `signup_date`, because the change feed doesn't include it.
- `dim_dates` covers only the dates in the data; in production it would span a fixed wide range with holiday and fiscal columns.

## How to run
1. Create the `VayuAir` database and import the six CSVs (Import Flat File wizard).
2. Run `sql/Q2.sql` to `sql/Q6.sql` in order. Q1 and Q7 are design and documentation only.
