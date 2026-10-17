# Transaction analysis

This is what I saw when I ran the scripts in this folder, and why it happened. All of it was done on MySQL 8.0 with the InnoDB engine, which is what every MarketLane table uses. InnoDB's default isolation level is `REPEATABLE READ`, which you can confirm with `SELECT @@transaction_isolation;`.

## Placing an order

An order at MarketLane is four tables changing together. If the stock update fails after the order row has gone in, the customer has an order for something they will never receive. If the payment row fails after the stock has been taken, the stock is gone and nobody paid for it. Wrapping the writes in a transaction means either all of them stay or none of them do.

**Commit.** The first order in `place-order.sql` is the normal case. Five statements run and `COMMIT` makes them permanent together. Before the commit, another session would not see any of them. After it, every session sees all of them.

**Rollback.** The second order fails on purpose. The stock update on product 6 tries to go from 0 to −1 and the `CHECK (quantity_on_hand >= 0)` constraint from Portfolio 1 refuses it with error 3819. What I found interesting is what MySQL does next: it undoes that one statement and leaves the transaction open. The order and item rows that went in before the failure are still there, visible to the session that wrote them. It is up to me to run `ROLLBACK`, and after that the order row is gone and product 6 is still at 0. An application would catch the error and roll back; a person at the keyboard has to remember to.

**Savepoint.** The third order has two items and only the first can be fulfilled. `SAVEPOINT after_first_item` marks the point after the first item went in. When the second item fails, `ROLLBACK TO SAVEPOINT` takes the transaction back to that mark without ending it. The first item is still there, and `COMMIT` saves the order with just that one. This is how a real checkout could drop an out-of-stock item and still complete the rest of the basket.

## Dirty read

A dirty read is seeing another session's change before that session has committed. The danger is that the change might be rolled back, in which case you have acted on a value that never existed.

Session B at `READ UNCOMMITTED` reads product 2's stock and gets 3. Session A sets it to 0 inside a transaction and does not commit. B reads again and gets 0. A rolls back. B reads a third time and gets 3. If B had been a checkout page, it would have told a customer the item was sold out when it never was.

Running the same steps with B at `REPEATABLE READ` gives 3 all three times. `READ UNCOMMITTED` is the only level that allows dirty reads, and I cannot think of a MarketLane query that would want it.

## Non-repeatable read

A non-repeatable read is asking the same question twice in one transaction and getting two different answers because someone else committed in between.

Session A at `READ COMMITTED` starts a transaction and reads stock, 3. Session B sells one unit and commits. A reads again, still in the same transaction, and gets 2. Nothing A did changed the value, but the value changed. For a report that reads a figure at the top and uses it again at the bottom, that is a problem.

At `REPEATABLE READ`, A's second read gives 3. InnoDB took a snapshot of the data when A's transaction first read something, and every read in that transaction comes from the snapshot. After A commits and reads again outside the transaction, it sees 2. The committed change was always there; A just was not shown it until its own transaction was over.

## Lost update

This is the one that matters most for a shop, and it happens at the default isolation level.

Two customers want the last few units of product 2. Both sessions read the stock and get 3. Each one works out that after its sale the stock should be 2, and writes 2. Both commit. The stock is 2. Two units were sold. One sale has been lost from the stock count, and MarketLane will oversell that product.

`REPEATABLE READ` does not stop this. It keeps each session's reads consistent, but B's write is a plain `UPDATE` that sets the column to 2, and there is nothing wrong with that statement on its own. The problem is that the value 2 was calculated from a read that was already stale by the time B wrote it. The isolation level protects reads; it does not know that a later write depends on an earlier read.

The fix is to tell the database that the read is the start of a change: `SELECT ... FOR UPDATE`. This takes a lock on the row at the moment of reading. When A runs it first, A holds the lock. When B runs it, B waits. In Workbench that step just sits on "Running". As soon as A commits, B's read goes through and returns 2, not 3, because A's write is now committed and B's lock means it is reading the latest value. B writes 1. Both sales are counted.

There is a shorter way to do the same thing for a simple stock change: `UPDATE inventory SET quantity_on_hand = quantity_on_hand - 1 WHERE product_id = 2 AND quantity_on_hand > 0`. The subtraction happens inside the engine under the row lock, so there is no gap between reading and writing. The `FOR UPDATE` version is for when the application needs to look at the value and decide what to do before writing.

## Deadlock

A deadlock is two sessions each holding a lock the other needs. Neither can continue and neither will give up on its own.

Session A updates product 1 and now holds a lock on that row. Session B updates product 2 and holds that one. A then tries to update product 2 and has to wait for B. B then tries to update product 1 and has to wait for A. That is the circle.

InnoDB checks for this every time a lock wait starts. It found the circle as soon as B's second update ran, picked B as the one to kill, rolled B's whole transaction back and returned error 1213, "Deadlock found when trying to get lock; try restarting transaction". A's blocked update then went through, and A committed. The final stock was 24 on product 1 and 2 on product 2, which is A's two updates and nothing from B.

`SHOW ENGINE INNODB STATUS` keeps a report of the most recent deadlock. It lists both transactions, the statement each was running, the row lock each held (shown as a record lock on the `PRIMARY` index of `inventory`) and the lock each was waiting for. It also says which one was rolled back. It is worth reading once to see that a row lock in InnoDB is literally a lock on an index record.

The usual way to avoid deadlocks is for every transaction to lock rows in the same order. If both sessions had updated product 1 before product 2, B would simply have waited for A to finish and then carried on. The one that gets error 1213 should be retried by the application, which is what the error message says.

## What I took from this

The transaction scripts and the constraints from Portfolio 1 work together. The `CHECK` constraint is what makes the rollback and savepoint demos fail in the right place, and the separate `inventory` table is what gives two sessions a single small row to contend for.

The isolation level is not a complete answer. `REPEATABLE READ` stopped the dirty read and the non-repeatable read without any extra work, but it did nothing for the lost update. That one needed a lock, and the lock needed me to know that the read was the start of a write.

Blocking is normal and short-lived. In the `FOR UPDATE` demo, B waited only as long as A took to commit. In a real system that is milliseconds. The deadlock, on the other hand, would have waited forever if InnoDB had not detected it, which is why detection is built in and the error should be handled rather than treated as a failure.
