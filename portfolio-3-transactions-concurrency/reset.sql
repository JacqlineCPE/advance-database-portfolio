-- Puts the three demo products back to their starting stock and removes
-- any orders created by the demos. Run before each concurrency demo.

USE marketlane;

-- generate-data.sql leaves exactly 100,005 orders, so anything above that is a demo order
DELETE FROM payment WHERE order_id > 100005;
DELETE FROM customer_order WHERE order_id > 100005;

UPDATE inventory SET quantity_on_hand = 25 WHERE product_id = 1;
UPDATE inventory SET quantity_on_hand = 3  WHERE product_id = 2;
UPDATE inventory SET quantity_on_hand = 0  WHERE product_id = 6;

SELECT product_id, quantity_on_hand FROM inventory WHERE product_id IN (1, 2, 6);