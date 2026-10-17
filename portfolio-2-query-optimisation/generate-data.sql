-- MarketLane bulk data generator
-- Run after e-commerce-database.sql and seed-data.sql
-- Adds ~20,000 customers, 5,000 products, 100,000 orders (~800,000 rows in total)

USE marketlane;

DROP TABLE IF EXISTS seq;
CREATE TABLE seq (n INT UNSIGNED NOT NULL PRIMARY KEY);

INSERT INTO seq (n)
WITH RECURSIVE d AS (
    SELECT 1 AS n UNION ALL SELECT n + 1 FROM d WHERE n < 1000
)
SELECT a.n + (b.n - 1) * 1000
FROM d a JOIN d b ON b.n <= 100;

START TRANSACTION;

INSERT INTO customer (full_name, email, phone)
SELECT CONCAT('Customer ', n),
       CONCAT('customer', n, '@example.com'),
       CONCAT('080', LPAD(n, 8, '0'))
FROM seq WHERE n <= 20000;

INSERT INTO address (customer_id, street, city, state, is_default)
SELECT c.customer_id,
       CONCAT(s.n, ' ', ELT(1 + s.n % 6, 'Airport', 'Sapele', 'Allen', 'Aba', 'Awolowo', 'Zaria'), ' Road'),
       ELT(1 + s.n % 8, 'Lagos', 'Abuja', 'Benin City', 'Kano', 'Port Harcourt', 'Ibadan', 'Enugu', 'Kaduna'),
       ELT(1 + s.n % 8, 'Lagos', 'FCT', 'Edo', 'Kano', 'Rivers', 'Oyo', 'Enugu', 'Kaduna'),
       TRUE
FROM seq s
JOIN customer c ON c.email = CONCAT('customer', s.n, '@example.com')
WHERE s.n <= 20000;

INSERT INTO product (category_id, sku, name, description, unit_price)
SELECT 1 + n % 5,
       CONCAT('SKU-G-', LPAD(n, 6, '0')),
       CONCAT(ELT(1 + n % 5, 'Gadget', 'Phone', 'Outfit', 'Kitchenware', 'Grocery item'), ' ', n),
       CONCAT('Generated product number ', n),
       ROUND(1000 + (n * 7919) % 199000, 2)
FROM seq WHERE n <= 5000;

INSERT INTO product_attribute (product_id, attribute_name, attribute_value)
SELECT p.product_id, 'colour', ELT(1 + p.product_id % 6, 'Black', 'White', 'Blue', 'Red', 'Green', 'Grey')
FROM product p WHERE p.sku LIKE 'SKU-G-%'
UNION ALL
SELECT p.product_id, 'brand', ELT(1 + p.product_id % 7, 'Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf')
FROM product p WHERE p.sku LIKE 'SKU-G-%'
UNION ALL
SELECT p.product_id, 'storage', ELT(1 + (p.product_id DIV 6) % 4, '64GB', '128GB', '256GB', '512GB')
FROM product p WHERE p.sku LIKE 'SKU-G-%' AND p.category_id IN (1, 2);

INSERT INTO inventory (product_id, quantity_on_hand, reorder_level)
SELECT product_id, (product_id * 13) % 200, IF(product_id % 3 = 0, 10, 5)
FROM product WHERE sku LIKE 'SKU-G-%';

SET @addr_count = (SELECT COUNT(*) FROM address);

INSERT INTO customer_order (customer_id, address_id, order_date, status, total_amount)
SELECT a.customer_id,
       a.address_id,
       TIMESTAMP('2024-10-15') + INTERVAL (s.n * 7919) % 730 DAY + INTERVAL (s.n * 104729) % 86400 SECOND,
       CASE
           WHEN s.n % 100 < 60 THEN 'delivered'
           WHEN s.n % 100 < 75 THEN 'shipped'
           WHEN s.n % 100 < 85 THEN 'paid'
           WHEN s.n % 100 < 93 THEN 'pending'
           ELSE 'cancelled'
       END,
       0
FROM seq s
JOIN address a ON a.address_id = 1 + (s.n * 7907) % @addr_count
WHERE s.n <= 100000;

SET @prod_count = (SELECT COUNT(*) FROM product);

INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT o.order_id,
       p.product_id,
       1 + (o.order_id + k.n) % 3,
       p.unit_price
FROM customer_order o
JOIN seq k ON k.n <= 1 + o.order_id % 4
JOIN product p ON p.product_id = 1 + (o.order_id * 31 + k.n * 131) % @prod_count
WHERE o.order_id > 5;

UPDATE customer_order o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS total
      FROM order_item GROUP BY order_id) t ON t.order_id = o.order_id
SET o.total_amount = t.total
WHERE o.order_id > 5;

INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
SELECT order_id,
       total_amount,
       ELT(1 + order_id % 3, 'card', 'bank_transfer', 'pay_on_delivery'),
       CASE status
           WHEN 'pending'   THEN 'initiated'
           WHEN 'cancelled' THEN 'refunded'
           ELSE 'successful'
       END,
       CONCAT('PAY-', LPAD(order_id, 8, '0')),
       IF(status = 'pending', NULL, order_date + INTERVAL 90 SECOND)
FROM customer_order WHERE order_id > 5;

INSERT INTO payment (order_id, amount, method, status, reference, paid_at)
SELECT order_id, total_amount, 'bank_transfer', 'failed', CONCAT('PAY-', LPAD(order_id, 8, '0'), '-F'), NULL
FROM customer_order WHERE order_id > 5 AND order_id % 20 = 0;

INSERT INTO delivery (order_id, courier_name, tracking_number, status, dispatched_at, delivered_at)
SELECT order_id,
       ELT(1 + order_id % 4, 'GIG Logistics', 'Kwik Delivery', 'DHL Nigeria', 'Red Star Express'),
       CONCAT('TRK-ML-', LPAD(order_id, 8, '0')),
       IF(status = 'delivered', 'delivered', 'in_transit'),
       order_date + INTERVAL 1 DAY,
       IF(status = 'delivered', order_date + INTERVAL 3 DAY, NULL)
FROM customer_order
WHERE order_id > 5 AND status IN ('shipped', 'delivered');

INSERT INTO delivery_status_history (delivery_id, status, location, recorded_at)
SELECT d.delivery_id, 'pending', 'Warehouse', o.order_date + INTERVAL 1 HOUR
FROM delivery d JOIN customer_order o ON o.order_id = d.order_id WHERE d.delivery_id > 2
UNION ALL
SELECT d.delivery_id, 'dispatched', 'Dispatch hub', d.dispatched_at
FROM delivery d WHERE d.delivery_id > 2
UNION ALL
SELECT d.delivery_id, 'in_transit', 'Sorting centre', d.dispatched_at + INTERVAL 6 HOUR
FROM delivery d WHERE d.delivery_id > 2
UNION ALL
SELECT d.delivery_id, 'delivered', 'Customer address', d.delivered_at
FROM delivery d WHERE d.delivery_id > 2 AND d.status = 'delivered';

COMMIT;

DROP TABLE seq;

SELECT 'customer' AS table_name, COUNT(*) AS row_count FROM customer
UNION ALL SELECT 'address', COUNT(*) FROM address
UNION ALL SELECT 'product', COUNT(*) FROM product
UNION ALL SELECT 'product_attribute', COUNT(*) FROM product_attribute
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL SELECT 'customer_order', COUNT(*) FROM customer_order
UNION ALL SELECT 'order_item', COUNT(*) FROM order_item
UNION ALL SELECT 'payment', COUNT(*) FROM payment
UNION ALL SELECT 'delivery', COUNT(*) FROM delivery
UNION ALL SELECT 'delivery_status_history', COUNT(*) FROM delivery_status_history;