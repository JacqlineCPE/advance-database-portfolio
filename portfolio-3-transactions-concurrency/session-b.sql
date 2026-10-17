-- SESSION B
-- Open this in a second Workbench tab alongside session-a.sql.
-- Run ONE step at a time, in the order given in each demo's header.

USE marketlane;
SELECT CONNECTION_ID();        -- must differ from the number in session A


-- ============================================================
-- DEMO 1: DIRTY READ
-- Order of steps: B1, A1, B2, A2, B3, then B4, A1, B2, A2, B3
-- ============================================================

-- B1: the lowest isolation level
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
START TRANSACTION;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 3

-- B2: after A has updated but not committed
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 0: a dirty read of A's uncommitted change

-- B3: after A rolled back
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 3: the value B saw a moment ago never existed
COMMIT;

-- B4: now repeat at the default level. Run B4, then A1, B2, A2, B3 again.
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 3
-- This time B2 shows 3, not 0. REPEATABLE READ does not show uncommitted changes.


-- ============================================================
-- DEMO 2: NON-REPEATABLE READ
-- Order of steps: A3, B5, A4, then run reset.sql, then A5, B5, A6
-- ============================================================

-- B5: sell one unit and commit while A's transaction is still open
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 2;
COMMIT;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 2, committed


-- ============================================================
-- DEMO 3: LOST UPDATE
-- Order of steps: run reset.sql, then A7, B6, A8, B7
-- ============================================================

-- B6: read the stock
START TRANSACTION;
SELECT quantity_on_hand FROM inventory WHERE product_id = 2;   -- 3

-- B7: write back 3 - 1. This does NOT fail.
UPDATE inventory SET quantity_on_hand = 2 WHERE product_id = 2;
COMMIT;
SELECT quantity_on_hand FROM inventory WHERE product_id = 2;   -- 2. Two units were sold but stock only dropped by one.


-- ============================================================
-- DEMO 3 FIX: SELECT ... FOR UPDATE
-- Order of steps: run reset.sql, then A9, B8 (hangs), A10, then B9
-- ============================================================

-- B8: this statement WAITS until A commits, because A holds the row lock.
-- Workbench will sit on "Running". Go to session A and run A10.
START TRANSACTION;
SELECT quantity_on_hand FROM inventory WHERE product_id = 2 FOR UPDATE;   -- 2, not 3: B sees A's committed write

-- B9: write back 2 - 1
UPDATE inventory SET quantity_on_hand = 1 WHERE product_id = 2;
COMMIT;
SELECT quantity_on_hand FROM inventory WHERE product_id = 2;   -- 1. Both sales counted.


-- ============================================================
-- DEMO 4: DEADLOCK
-- Order of steps: run reset.sql, then A11, B10, A12 (A hangs), B11
-- ============================================================

-- B10
START TRANSACTION;
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 2;

-- B11: this closes the circle. InnoDB sees the deadlock at once and picks a victim.
-- Expected: ERROR 1213 Deadlock found when trying to get lock; try restarting transaction
-- B's whole transaction is rolled back. A's blocked update then goes through.
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 1;

-- B12: B's work is gone; only A's two updates are in the table
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id IN (1, 2);   -- 24 and 2


ROLLBACK;