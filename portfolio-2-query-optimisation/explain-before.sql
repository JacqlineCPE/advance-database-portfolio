-- Baseline execution plans, captured BEFORE adding any indexes
-- Each EXPLAIN ANALYZE actually runs the query and reports real timings

USE marketlane;

-- Q1: Order history for one customer
EXPLAIN ANALYZE
SELECT o.order_id, o.order_date, o.status, o.total_amount,
       COUNT(i.order_item_id) AS items
FROM customer_order o
JOIN order_item i ON i.order_id = o.order_id
WHERE o.customer_id = 1234
GROUP BY o.order_id, o.order_date, o.status, o.total_amount
ORDER BY o.order_date DESC;

-- Q2: Monthly revenue for the last 12 months
EXPLAIN ANALYZE
SELECT DATE_FORMAT(order_date, '%Y-%m') AS month,
       COUNT(*) AS orders,
       SUM(total_amount) AS revenue
FROM customer_order
WHERE status IN ('paid', 'shipped', 'delivered')
  AND order_date >= '2025-10-01' AND order_date < '2026-10-01'
GROUP BY month
ORDER BY month;

-- Q3: Top 10 products by units sold in a date range
EXPLAIN ANALYZE
SELECT p.product_id, p.name, c.name AS category,
       SUM(i.quantity) AS units_sold,
       SUM(i.quantity * i.unit_price) AS revenue
FROM order_item i
JOIN customer_order o ON o.order_id = i.order_id
JOIN product p ON p.product_id = i.product_id
JOIN category c ON c.category_id = p.category_id
WHERE o.status = 'delivered'
  AND o.order_date BETWEEN '2026-01-01' AND '2026-06-30 23:59:59'
GROUP BY p.product_id, p.name, c.name
ORDER BY units_sold DESC
LIMIT 10;

-- Q4: Products at or below reorder level
EXPLAIN ANALYZE
SELECT p.sku, p.name, inv.quantity_on_hand, inv.reorder_level,
       inv.reorder_level - inv.quantity_on_hand AS shortfall
FROM inventory inv
JOIN product p ON p.product_id = inv.product_id
WHERE inv.quantity_on_hand <= inv.reorder_level
  AND p.is_active = TRUE
ORDER BY shortfall DESC;

-- Q5: Latest status of every in-transit delivery
EXPLAIN ANALYZE
SELECT d.delivery_id, d.tracking_number, d.courier_name,
       h.status AS latest_status, h.location, h.recorded_at
FROM delivery d
JOIN delivery_status_history h ON h.delivery_id = d.delivery_id
WHERE d.status = 'in_transit'
  AND h.recorded_at = (SELECT MAX(h2.recorded_at)
                       FROM delivery_status_history h2
                       WHERE h2.delivery_id = d.delivery_id)
ORDER BY h.recorded_at DESC
LIMIT 50;

-- Q6: Products matching two attributes
EXPLAIN ANALYZE
SELECT p.product_id, p.name, p.unit_price
FROM product p
JOIN product_attribute a1 ON a1.product_id = p.product_id
                         AND a1.attribute_name = 'colour' AND a1.attribute_value = 'Black'
JOIN product_attribute a2 ON a2.product_id = p.product_id
                         AND a2.attribute_name = 'storage' AND a2.attribute_value = '128GB'
WHERE p.is_active = TRUE
ORDER BY p.unit_price;

-- Q7: Customers ranked by spend within their state
EXPLAIN ANALYZE
SELECT state, full_name, total_spent, state_rank
FROM (
    SELECT a.state, c.full_name,
           SUM(o.total_amount) AS total_spent,
           RANK() OVER (PARTITION BY a.state ORDER BY SUM(o.total_amount) DESC) AS state_rank
    FROM customer_order o
    JOIN customer c ON c.customer_id = o.customer_id
    JOIN address a ON a.address_id = o.address_id
    WHERE o.status = 'delivered'
    GROUP BY a.state, c.customer_id, c.full_name
) ranked
WHERE state_rank <= 3
ORDER BY state, state_rank;

-- Q8: Pending orders with no successful payment
EXPLAIN ANALYZE
SELECT o.order_id, o.order_date, o.total_amount, c.email
FROM customer_order o
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.status = 'pending'
  AND NOT EXISTS (SELECT 1 FROM payment p
                  WHERE p.order_id = o.order_id AND p.status = 'successful')
  AND o.order_date < '2026-10-01'
ORDER BY o.order_date
LIMIT 100;