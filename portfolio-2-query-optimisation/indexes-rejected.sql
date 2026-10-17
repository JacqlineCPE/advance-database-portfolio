-- Indexes I tried and removed, with the reason each one was rejected.
-- These are NOT part of the final schema. Kept as evidence of the decision process.

USE marketlane;

-- Rejected 1: status on its own.
-- Every status value matches thousands of rows (60% of orders are 'delivered'),
-- so the optimiser never chose this index over a table scan. It was dead weight.
-- CREATE INDEX idx_order_status_only ON customer_order (status);

-- Rejected 2: a covering index on order_item for Q3.
-- The optimiser preferred the existing uq_order_product unique key, which is
-- narrower and already covers the join. This 8.5 MB index was never used.
-- CREATE INDEX idx_item_order_product_qty ON order_item (order_id, product_id, quantity, unit_price);

-- Rejected 3: date first, status second.
-- Q2 and Q3 filter on an equality (status) and a range (order_date). MySQL can only
-- use an index range on the LAST column it filters, so (status, order_date) lets it
-- seek to one status and scan a date range, while (order_date, status) would have to
-- scan every date in the range and check status on each row. Column order matters.
-- CREATE INDEX idx_order_date_status ON customer_order (order_date, status);