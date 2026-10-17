# Portfolio 3: Transactions and Concurrency

This is the third part of my Advanced Database Systems portfolio (MIT 8103). It uses the MarketLane database from Portfolio 1 with the data loaded in Portfolio 2. The work was to show an order being placed as a transaction, with commit, rollback and savepoint, and then to run two sessions against the same rows at the same time to see what goes wrong at each isolation level and how to stop it.

Everything was done on MySQL 8.0 using MySQL Workbench. The two-session demos use two query tabs in Workbench, each of which gets its own connection to the server.

## What is in this folder

| File | What it is |
|---|---|
| `place-order.sql` | Three transactions in one tab: commit, rollback, and savepoint |
| `session-a.sql` | One side of the four two-session demos |
| `session-b.sql` | The other side |
| `reset.sql` | Puts the three demo products back to their starting stock and removes demo orders |
| `transaction-analysis.md` | What happened in each demo and why |

The rows used throughout are three products from the seed data: product 1 (Smartphone X10, stock 25), product 2 (Smartphone Pro, stock 3) and product 6 (Leather Sandals, stock 0). Product 2 is the one two customers fight over, and product 6 is the one that makes a stock update fail.

## Placing an order as a transaction

Placing an order touches four tables: a row in `customer_order`, one or more rows in `order_item`, a stock change in `inventory`, and a row in `payment`. If any of those fails the others must not stay behind, so the whole thing runs between `START TRANSACTION` and `COMMIT`.

`place-order.sql` does this three times.

The first order goes through normally. Customer 2 buys one Smartphone Pro, all five writes succeed, and `COMMIT` makes them permanent. Stock on product 2 drops from 3 to 2.

The second order is for Leather Sandals, which have no stock. The order row and the item row go in, then the stock update tries to take `quantity_on_hand` from 0 to −1 and fails the `CHECK` constraint from Portfolio 1 (error 3819). MySQL rolls back only that one statement, not the transaction, so a `SELECT` at that point still shows the order row. `ROLLBACK` then removes it. This is the atomicity part of ACID: the failed order leaves no trace.

![Error 3819 in the Workbench Action Output](rollback-error-screenshot.png)

This is the Action Output line for that failed update. The red cross is Workbench showing the statement was refused, and the message names the constraint that refused it, `chk_inventory_qty`. The order and item rows written just before it were still there until the `ROLLBACK` on the next line of the script.

The third order has two items. The first, a Smartphone X10, is fine. After it I set `SAVEPOINT after_first_item`. The second item is the Leather Sandals again and fails the same way. `ROLLBACK TO SAVEPOINT` undoes the second item but keeps the first, and `COMMIT` saves the order with one item in it. Stock on product 1 drops to 24; product 6 stays at 0.

Two of the statements in the file are meant to fail. Either switch on the "continue on error" toggle in the Workbench toolbar and run the whole file, or run it a block at a time with Ctrl+Enter.

## The two-session demos

`session-a.sql` and `session-b.sql` are opened in two Workbench tabs side by side. Each demo has a header giving the order to run the steps in, alternating between the tabs. The steps are labelled `A1`, `B1` and so on. You select one step and press Ctrl+Enter, then move to the other tab. Running the whole file with the lightning bolt would not work, because the point is that the two sessions are in the middle of their transactions at the same time.

Both files start with `SELECT CONNECTION_ID();`. The two numbers must be different. If they are the same the tabs are sharing a connection and nothing will block.

`reset.sql` goes between demos so stock is back at its starting value each time.

**Demo 1, dirty read.** Session B is set to `READ UNCOMMITTED`. Session A changes the stock to 0 without committing. B reads the stock and sees 0. A rolls back. B reads again and sees 3. The value B saw in the middle never existed. The same steps at `REPEATABLE READ` show 3 every time.

**Demo 2, non-repeatable read.** Session A is set to `READ COMMITTED` and reads the stock, 3, inside a transaction. B sells one and commits. A reads again, in the same transaction, and gets 2. At `REPEATABLE READ` the second read still gives 3, and A only sees 2 after its own transaction ends.

**Demo 3, lost update.** Both sessions read the stock, 3, the way an application would before deciding what to write. Both write back 2 and commit. Two units were sold but the stock only dropped by one. The fix is `SELECT ... FOR UPDATE`, which locks the row at the moment of reading. B's read then waits until A commits, sees 2, and writes 1.

**Demo 4, deadlock.** A locks product 1 and then asks for product 2. B locks product 2 and then asks for product 1. Each is waiting for the other. InnoDB spots this within a second, picks B, rolls it back with error 1213, and lets A finish. `SHOW ENGINE INNODB STATUS` has a section called `LATEST DETECTED DEADLOCK` that names both transactions and the rows they held.

Two steps hang on purpose: `B8` in the lost-update fix and `A12` in the deadlock. Workbench shows them as running. Go to the other tab and run the next step and they finish. MySQL waits up to 50 seconds for a lock before giving up.

## What happened

| Demo | Isolation level | What went wrong | What stopped it |
|---|---|---|---|
| 1 Dirty read | `READ UNCOMMITTED` | B read a value A had not committed and later rolled back | `REPEATABLE READ` |
| 2 Non-repeatable read | `READ COMMITTED` | A's second read of the same row gave a different answer | `REPEATABLE READ` |
| 3 Lost update | `REPEATABLE READ` | Both sessions overwrote each other; final stock 2 instead of 1 | `SELECT ... FOR UPDATE` |
| 4 Deadlock | `REPEATABLE READ` | Each session held a row the other needed | InnoDB rolled one back with error 1213 |

`transaction-analysis.md` goes through each of these in more detail, including why the lost update happens even at MySQL's default isolation level and what the deadlock report actually says.

## Running it in order

Start with the database as it was at the end of Portfolio 2, then:

1. Run `place-order.sql` in one tab.
2. Run `reset.sql`.
3. Open `session-a.sql` and `session-b.sql` in two tabs and check the connection IDs differ.
4. Work through demos 1 to 4, running `reset.sql` where the headers say to.
