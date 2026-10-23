-- MySQL replication runs off the binary log: the source writes every change to it
-- and each replica reads it and applies the same changes. This shows that log on
-- the single MySQL server from Portfolios 1 to 3. Run in Workbench, one block at a time.

USE marketlane;

-- 1. The log is on (MySQL 8 default) and the server has an id. Every member of a
--    replication setup needs a different server_id.
SHOW VARIABLES LIKE 'log_bin';
SHOW VARIABLES LIKE 'server_id';
SHOW VARIABLES LIKE 'binlog_format';

-- 2. The log files, and where the server is writing right now.
--    A new replica would be told to start reading from this file and position.
--    The two SET lines remember them for step 4.
SHOW BINARY LOGS;
SHOW MASTER STATUS;
SET @file = (SELECT LOCAL->>'$.binary_log_file'     FROM performance_schema.log_status);
SET @pos  = (SELECT LOCAL->>'$.binary_log_position' FROM performance_schema.log_status);
SELECT @file AS current_file, @pos AS current_position;

-- 3. Make a change
UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 8;

-- 4. Read the log from the position remembered in step 2. The rows show the UPDATE
--    as a Table_map event followed by an Update_rows event, wrapped in a transaction
--    (Gtid, Query BEGIN ... Xid COMMIT). That is exactly what a replica receives.
SET @sql = CONCAT('SHOW BINLOG EVENTS IN ''', @file, ''' FROM ', @pos, ' LIMIT 10');
PREPARE show_events FROM @sql;
EXECUTE show_events;
DEALLOCATE PREPARE show_events;

-- 5. Put the stock back
UPDATE inventory SET quantity_on_hand = quantity_on_hand + 1 WHERE product_id = 8;
