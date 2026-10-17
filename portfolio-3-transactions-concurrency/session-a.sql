-- SESSION A
-- Open this in one Workbench tab and session-b.sql in another.
-- Run ONE step at a time, alternating between the tabs in the order
-- given in each demo's header. Select the step's statements and press Ctrl+Enter.
-- Check first that the two tabs really are two connections:

USE marketlane;
SELECT CONNECTION_ID();        -- must differ from the number in session B


-- ============================================================
-- DEMO 1: DIRTY READ
-- Order of steps: B1, A1, B2, A2, B3, then B4, A1, B2, A2, B3
-- Session A changes stock but never commits. Does B see the change?
-- ============================================================

-- A1
START TRANSACTION;
UPDATE inventory SET quantity_on_hand = 0 WHERE product_id = 2;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 0, uncommitted

-- A2
ROLLBACK;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- back to 3


-- ============================================================
-- DEMO 2: NON-REPEATABLE READ
-- Order of steps: A3, B5, A4, then run reset.sql, then A5, B5, A6
-- Session A reads stock twice inside one transaction. B changes it in between.
-- ============================================================

-- A3: under READ COMMITTED
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 3

-- A4: same transaction, same query, after B committed
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 2: the value changed under me
COMMIT;

-- A5: under REPEATABLE READ (the MySQL default)
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 3

-- A6: same transaction, same query, after B committed
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- still 3: my snapshot is kept
COMMIT;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id = 2;   -- 2: now that my transaction is over


-- ============================================================
-- DEMO 3: LOST UPDATE
-- Order of steps: run reset.sql, then A7, B6, A8, B7
-- Two customers each read stock = 3, each decide to set it to 2.
-- ============================================================

-- A7: read the stock, the way an application would before deciding
START TRANSACTION;
SELECT quantity_on_hand FROM inventory WHERE product_id = 2;   -- 3

-- A8: write back 3 - 1
UPDATE inventory SET quantity_on_hand = 2 WHERE product_id = 2;
COMMIT;
SELECT quantity_on_hand FROM inventory WHERE product_id = 2;   -- 2


-- ============================================================
-- DEMO 3 FIX: SELECT ... FOR UPDATE
-- Order of steps: run reset.sql, then A9, B8 (B will hang), A10, then B9
-- Same as above but each session locks the row before reading it.
-- ============================================================

-- A9: lock the row, then read it
START TRANSACTION;
SELECT quantity_on_hand FROM inventory WHERE product_id = 2 FOR UPDATE;   -- 3

-- A10: write back and release the lock. B's step 8 finishes the moment this runs.
UPDATE inventory SET quantity_on_hand = 2 WHERE product_id = 2;
COMMIT;


-- ============================================================
-- DEMO 4: DEADLOCK
-- Order of steps: run reset.sql, then A11, B10, A12 (A will hang), B11
-- A locks product 1 then wants product 2. B locks product 2 then wants product 1.
-- ============================================================

-- A11
START TRANSACTION;
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 1;

-- A12: this waits, because B holds product 2
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 2;

-- A13: after B has been killed, A is free to finish
COMMIT;
SELECT product_id, quantity_on_hand FROM inventory WHERE product_id IN (1, 2);   -- 24 and 2

-- A14: InnoDB keeps a report of the last deadlock. Look for LATEST DETECTED DEADLOCK.
SHOW ENGINE INNODB STATUS;