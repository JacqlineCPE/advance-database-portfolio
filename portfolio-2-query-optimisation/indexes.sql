-- Indexes added after studying the baseline
-- Run once, then re-run explain-after.sql

USE marketlane;

-- For Q2, Q3, Q7, Q8: every one of these filters on status and/or order_date.
-- total_amount is included so Q2 can be answered from the index alone (covering index).
CREATE INDEX idx_order_status_date_total
    ON customer_order (status, order_date, total_amount);

-- For Q5: finds the history rows of one delivery already sorted by time,
-- so MAX(recorded_at) is a single index read instead of a scan of that delivery's rows.
CREATE INDEX idx_history_delivery_time
    ON delivery_status_history (delivery_id, recorded_at);

-- For Q5: only 20% of deliveries are in_transit, so this avoids scanning all 75,000.
CREATE INDEX idx_delivery_status
    ON delivery (status);

-- Refresh statistics so the optimiser sees the new indexes with accurate estimates
ANALYZE TABLE customer_order, delivery, delivery_status_history;

SHOW INDEX FROM customer_order;
SHOW INDEX FROM delivery;
SHOW INDEX FROM delivery_status_history;