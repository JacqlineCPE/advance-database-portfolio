# Performance analysis

This is what changed when I added indexes to the MarketLane database and ran the eight queries again. The plans I quote are in `explain-before.txt` and `explain-after.txt`. All timings are from `EXPLAIN ANALYZE` on my laptop. I ran each query twice and used the second run, so the data was already in memory both times.

## Before and after

| Query | Before | After | Change | What changed in the plan |
|---|---|---|---|---|
| Q1 Customer order history | 0.3 ms | 3 ms | none | Same plan: index lookup on `fk_order_customer` |
| Q2 Monthly revenue | 384 ms | 216 ms | −44% | Table scan of 100,005 rows → covering index scan returning 42,467 |
| Q3 Top products in a period | 1,638 ms | 1,551 ms | −5% | Table scan on orders → index range scan; the rest is the same |
| Q4 Reorder list | 45 ms | 112 ms | none | Same plan: scan of 5,008 products |
| Q5 Latest delivery status | 1,395 ms | 1,064 ms | −24% | Table scan on deliveries → index lookup; subquery still runs 45,003 times |
| Q5b Q5 rewritten with a window function | — | 1,009 ms | −28% against Q5 before | No subquery; one sort of 45,003 rows instead |
| Q6 Attribute filter | 98 ms | 181 ms | none | Same plan: `uq_product_attribute` was already being used |
| Q7 Spend rank by state | 1,036 ms | 1,111 ms | +7% | Index used, but it reads 60% of the table so it does not help |
| Q8 Unpaid pending orders | 142 ms | 21 ms | −85% | Table scan plus a sort → index range scan with no sort |

Q1, Q4 and Q6 show a higher number after, but their plans did not change at all. They are small queries and the difference is just the laptop doing other things at the time. A single timing of a fast query does not tell you much. Q8 going from 142 ms to 21 ms with a different plan does.

## The indexes I kept

These are in `indexes.sql`.

**`idx_order_status_date_total` on `customer_order (status, order_date, total_amount)`.** Four of the eight queries filter orders on `status`, and three of those also use `order_date`. With `status` first, the engine can jump to one status and then read a range of dates inside it. I put `total_amount` on the end so Q2 can get everything it needs from the index without reading the table. That is what "covering index range scan" means in the Q2 after-plan.

**`idx_history_delivery_time` on `delivery_status_history (delivery_id, recorded_at)`.** For Q5. Before, finding the latest history row for a delivery meant fetching all three of its rows through `fk_history_delivery` and comparing each one to the subquery result. After, the lookup uses both columns and goes straight to the one matching row. The subquery's own lookup also became a covering lookup, so it reads the index and not the table.

**`idx_delivery_status` on `delivery (status)`.** Also for Q5. Only 15,001 of the 75,002 deliveries are in transit. Reading those through the index took 68 ms; scanning the whole table and filtering took 117 ms.

## The indexes I tried and removed

These are in `indexes-rejected.sql` with the reasons.

An index on `customer_order (status)` by itself was never picked. Every status value matches at least 7% of the table and the most common one matches 60%, so a table scan is cheaper.

A covering index on `order_item (order_id, product_id, quantity, unit_price)` for Q3 was ignored. The unique key `uq_order_product` already lets the engine find an order's items and it is narrower. Both plans for Q3 show `uq_order_product` being used. The extra index took 8.5 MB and did nothing.

I also thought about `(order_date, status)` instead of `(status, order_date)`. MySQL can only use a range on the last index column it reads, so with `status` first it seeks to one status and scans a date range. With `order_date` first it would scan the whole date range and check `status` on every entry.

## What I found

**An index helps when it cuts the rows down a lot.** Q8 filters to about 8% of orders and got seven times faster. Q7 filters to 60% and got no faster. The after-plan for Q7 shows the index lookup on 60,001 rows taking 304 ms. In the before-plan, scanning all 100,005 rows and filtering took 176 ms. The index was slower because each of the 60,001 entries still needed a trip to the table row for `customer_id` and `address_id`. The optimiser picked the index anyway, so its cost estimate was wrong here.

**An index fixes one step, not the whole query.** In Q3 the orders step went from 269 ms to 70 ms, but the query still took 1.5 seconds. The slow part is higher up. The optimiser joined the five categories to the 37,148 order items with a hash join that has no join condition, which gives 185,740 rows, and then did a product lookup on every one of them. That is the same before and after, and no index on `customer_order` can change it. For a monthly report I would keep a summary table instead.

**Sometimes the query is the problem.** Q5's correlated subquery runs once per candidate row, 45,003 times in both plans. The index made each run cheaper (0.0165 ms down to 0.0124 ms) but could not reduce the count. Q5b replaces the subquery with `ROW_NUMBER()` and does the work as one sort. It is a little faster than the indexed Q5. There are 15,001 deliveries with three history rows each, so 45,003 rows have to be handled whichever way it is written, but the Q5b plan is simpler and would hold up better as the history table grows.

**Q8 got faster for two reasons.** The index replaced the table scan. It also stores rows in `order_date` order within each status, so the `ORDER BY` was already done. The before-plan has a sort step over 7,863 rows. The after-plan has none, and because there is no sort the engine stops after the first 100 rows. The plan shows `rows=100` coming out of the index scan.

**InnoDB already indexes foreign keys.** Q1 and Q6 were quick before I did anything. Every foreign key in the Portfolio 1 schema got an index automatically, and `uq_product_attribute` doubles as the lookup index for Q6. Checking `SHOW INDEX` first saved me from adding things that were already there.

**Statistics matter.** `indexes.sql` ends with `ANALYZE TABLE` so the optimiser's row estimates are refreshed. You can see them change between the two plan files. The Q2 filter is estimated at 5,552 rows before and 68,414 after, against an actual 42,467 both times. The Q8 before-plan estimated 99,960 rows would pass the filter when only 7,863 did. Bad estimates lead to bad plan choices.

## The cost of indexes

Every index has to be updated on every insert, update and delete of the columns it covers. `customer_order` now has four indexes, so each new order writes four index entries as well as the row. For MarketLane that is fine: an order is written once and read many times. I would be more careful on `delivery_status_history` if it were being written at high volume, since Q5 is a dashboard query and could live with a slower refresh.
