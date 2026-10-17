-- MarketLane: placing an order as a transaction
-- Run in ONE Workbench tab. Two of the statements are meant to fail, so either
-- switch on "continue on error" (toolbar toggle) and run the whole file, or run
-- it one block at a time with Ctrl+Enter.
-- Products used: 1 (stock 25), 2 (stock 3), 6 (stock 0).

USE marketlane;

-- Starting stock
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id IN (1, 2, 6);


-- ============================================================
-- T1: a successful order, ended with COMMIT
-- Customer 2 buys one Smartphone Pro (product 2).
-- Five writes that must all happen or none happen.
-- ============================================================

START TRANSACTION;

INSERT INTO customer_order (customer_id, address_id, status)
VALUES (2, 3, 'pending');
SET @order_id = LAST_INSERT_ID();

INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT @order_id, product_id, 1, unit_price FROM product WHERE product_id = 2;

UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 2;

UPDATE customer_order
SET total_amount = (SELECT SUM(quantity * unit_price) FROM order_item WHERE order_id = @order_id)
WHERE order_id = @order_id;

INSERT INTO payment (order_id, amount, method, status, reference)
SELECT @order_id, total_amount, 'card', 'initiated', CONCAT('PAY-T1-', @order_id)
FROM customer_order WHERE order_id = @order_id;

COMMIT;

-- Expected: the order exists with one item, stock on product 2 is now 2
SELECT o.order_id, o.status, o.total_amount, i.product_id, i.quantity, p.reference
FROM customer_order o
JOIN order_item i ON i.order_id = o.order_id
JOIN payment p ON p.order_id = o.order_id
WHERE o.order_id = @order_id;

SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;


-- ============================================================
-- T2: an order that cannot be fulfilled, ended with ROLLBACK
-- Customer 3 tries to buy Leather Sandals (product 6), which has no stock.
-- The stock update fails the CHECK constraint. MySQL rolls back only that
-- one statement, so the order and item rows are still pending until we
-- ROLLBACK ourselves.
-- ============================================================

START TRANSACTION;

INSERT INTO customer_order (customer_id, address_id, status)
VALUES (3, 4, 'pending');
SET @order_id = LAST_INSERT_ID();

INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT @order_id, product_id, 1, unit_price FROM product WHERE product_id = 6;

-- Expected: ERROR 3819 Check constraint 'chk_inventory_qty' is violated
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 6;

-- The order row is still there inside this transaction (1 row)
SELECT order_id, status FROM customer_order WHERE order_id = @order_id;

ROLLBACK;

-- Expected: 0 rows. Nothing from T2 survived.
SELECT order_id, status FROM customer_order WHERE order_id = @order_id;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 6;


-- ============================================================
-- T3: a partly successful order, using SAVEPOINT
-- Customer 1 orders a Smartphone X10 (product 1) and Leather Sandals (product 6).
-- The first item is fine. The second fails. Roll back to the savepoint,
-- keep the first item, and commit the order with just that.
-- ============================================================

START TRANSACTION;

INSERT INTO customer_order (customer_id, address_id, status)
VALUES (1, 1, 'pending');
SET @order_id = LAST_INSERT_ID();

INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT @order_id, product_id, 1, unit_price FROM product WHERE product_id = 1;
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 1;

SAVEPOINT after_first_item;

INSERT INTO order_item (order_id, product_id, quantity, unit_price)
SELECT @order_id, product_id, 1, unit_price FROM product WHERE product_id = 6;

-- Expected: ERROR 3819 Check constraint 'chk_inventory_qty' is violated
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 6;

-- Undo the second item but keep the first
ROLLBACK TO SAVEPOINT after_first_item;

UPDATE customer_order
SET total_amount = (SELECT SUM(quantity * unit_price) FROM order_item WHERE order_id = @order_id)
WHERE order_id = @order_id;

COMMIT;

-- Expected: one item (product 1), total 185000.00, product 1 stock 24, product 6 still 0
SELECT o.order_id, o.total_amount, i.product_id, i.quantity
FROM customer_order o
JOIN order_item i ON i.order_id = o.order_id
WHERE o.order_id = @order_id;

SELECT product_id, quantity_on_hand FROM inventory WHERE product_id IN (1, 6);