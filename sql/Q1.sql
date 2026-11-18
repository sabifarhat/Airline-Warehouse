/* =====================================================================
   Q1 - GRAIN AND COLUMN CLASSIFICATION
   =====================================================================
   GRAIN: One row per booking (ticket): one passenger on one flight.
   booking_id is unique per row and stays on the fact (degenerate dimension).

   Caveat: booking_status holds only the latest status from the source.
   Status history is not kept. To keep historical data, the fact could store one row
   per status change with effective dates or a status change date. This is
   the same versioning idea as SCD Type 2, but applied to an event


   Source: bronze_bookings joined to bronze_flights on flight_id.

   Column               | Label                         | Description
   ---------------------|-------------------------------|----------------------------------------
   booking_id           | Dimension key (degenerate)    | Unique booking ID; a dimension table of its own could be redundant
   passenger_id         | Dimension key                 | From bronze_passengers (who flew)
   flight_id            | Dimension key                 | From bronze_flights (which flight); also the join key to bronze_flights
   booking_date         | Dimension key                 | Joins on date col in DimDate or DimCalendar as booking date (when booked)
   travel_date          | Dimension key                 | Joins on date col in DimDate or DimCalendar as travel date (when flown)
   fare_class           | Dimension attribute           | Economy / Premium Economy / Business / First; for filtering and grouping
   booking_status       | Dimension attribute           | Confirmed / Cancelled / NoShow; revenue = Confirmed only
   fare_amount          | Measure (additive)            | Base fare 
   tax_amount           | Measure (additive)            | Taxes and fees
   miles_earned         | Measure (additive)            | Loyalty miles credited
   flight_number        | Attribute in bronze_flights   | For flight identification
   flight_date          | Attribute of bronze_flights   | Date the flight operates
   origin_airport_code  | Dimension key                 | From bronze_airports as origin
   dest_airport_code    | Dimension key                 | From bronze_airports as destination
   aircraft_code        | Dimension key                 | From bronze_aircraft