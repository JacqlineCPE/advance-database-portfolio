# Suitability: where each data model fits MarketLane

I implemented the document model in MongoDB because it fits the largest part of MarketLane. The other three NoSQL models each fit one corner of the system better than either MySQL or MongoDB would. This file goes through all four and ends with what I would actually run.

## Document model (MongoDB), implemented

**Where it fits.** The product catalogue and the orders.

Products have attributes that differ by type. In MySQL that forced the `product_attribute` name/value table, and every attribute filter was a self-join. In MongoDB each product has only the attributes it needs, as fields, and one wildcard index covers them all. Adding a new attribute like `wattage` for a new category needs no schema change and no migration.

Orders are read as a whole far more often than they are picked apart. The order page, the receipt, the tracking page and the customer's history all want the full order. Six MySQL tables and their joins become one document and one read. Writing a status update is a `$push` into the embedded history instead of an insert into a separate table.

The Portfolio 2 queries all have a MongoDB form, and most are simpler. Q6 (two-attribute filter) went from a self-join to a filter. Q5 (latest delivery status) went from a correlated subquery that ran 45,003 times to reading the last element of an array. Q1 (a customer's orders with item counts) went from a join and a `GROUP BY` to a `find` with `$size`.

**Where it does not fit.** Anything that cuts across documents.

Monthly revenue (Q2) and top products (Q3) still work, through the aggregation pipeline, but they scan every order and unpack every items array. On 100,000 orders that is the same full scan MySQL did before indexing, and there is no covering index trick to avoid it. For real reporting I would keep a summary collection updated as orders are placed, or run the reports from a copy of the data in a column store.

Cross-document consistency is on the application. Placing an order means decrementing stock in `products` and inserting into `orders`. On a single MongoDB server those are two separate writes and the second can fail after the first succeeded. Multi-document transactions exist in MongoDB, but only on a replica set, which is what Portfolio 5 sets up. Until then the atomic `findOneAndUpdate` on stock is the guard, and a failed order insert would need the stock put back by hand.

Referential integrity is also on the application. An order can point at a product that was deleted. Schema validation can check types and ranges inside a document but cannot check that `product_id` 99 exists in another collection.

## Key-value model (Redis), discussed

**Where it fits.** The shopping cart, sessions, and the stock counter under load.

A cart is one customer's temporary list, read and written on every click, thrown away or turned into an order within minutes. It does not need a schema, joins or history. In Redis it is a hash under a key:

```
HSET cart:customer:2 product:5 2 product:6 1     // 2 shirts, 1 pair of sandals
HGETALL cart:customer:2
EXPIRE cart:customer:2 86400                      // gone after a day
```

Every operation is a single key lookup in memory, in microseconds. A login session is the same shape: `SET session:a1b2c3 '{"customer_id":2}' EX 1800`.

Flash-sale stock is the other case. Ten thousand people clicking "buy" on the same product would queue on one row lock in MySQL or one document lock in MongoDB. In Redis, `DECR stock:product:2` is atomic and serves hundreds of thousands of decrements a second; the application rejects the sale when the result goes below zero and writes the real order to MongoDB afterwards.

**Where it does not fit.** Anything you need to query by something other than the key. You cannot ask Redis for "all carts containing product 5" without maintaining a second structure yourself, and data in memory is lost on restart unless persistence is configured. Redis holds the fast, short-lived parts of MarketLane, not the record of what happened.

## Column-family model (Cassandra), discussed

**Where it fits.** The delivery status history, and any other event stream that grows forever.

Delivery history is append-only, written by courier scanners in large volumes, and read one delivery at a time in time order. In MySQL it was the largest table (285,007 rows in Portfolio 2). In MongoDB I embedded it, which is fine while a delivery has five events but would not be if a courier reported GPS positions every minute. Cassandra is built for exactly this shape. The table is designed around the query:

```
CREATE TABLE delivery_events (
    tracking_number text,
    recorded_at     timestamp,
    status          text,
    location        text,
    PRIMARY KEY (tracking_number, recorded_at)
) WITH CLUSTERING ORDER BY (recorded_at DESC);
```

`tracking_number` is the partition key, so all events for one delivery sit together on one node. `recorded_at` is the clustering key, so they are stored in time order and "latest status" is the first row of the partition with no sorting. Writes go to any node and never block on each other, and the table can grow across many machines by adding nodes.

**Where it does not fit.** Everything else. Cassandra only answers the queries its tables were designed for. "Which deliveries passed through Ikeja hub today" needs a second table keyed by location and date, written at the same time. There are no joins, no aggregation worth the name, and no transactions. It would be the wrong place for products, customers or orders.

## Graph model (Neo4j), discussed

**Where it fits.** Recommendations, and anything else about how things connect.

"Customers who bought this also bought" is a question about paths between nodes, and it is painful in both SQL and MongoDB: self-join `order_item` to itself through `order_id`, or `$unwind` and `$group` across every order. In a graph it is a pattern match:

```
MATCH (p:Product {sku: "SKU-PH-001"})<-[:CONTAINS]-(:Order)-[:CONTAINS]->(other:Product)
RETURN other.name, count(*) AS together
ORDER BY together DESC LIMIT 5
```

Customers, orders and products are nodes; `PLACED` and `CONTAINS` are relationships. Following a relationship is a pointer dereference, not an index lookup, so a query that goes three or four hops out (people who bought what you bought also bought) does not slow down as the database grows the way a chain of joins does. Fraud patterns are the same shape: several accounts sharing one delivery address and one card.

**Where it does not fit.** Bulk reads and totals. Monthly revenue is not a graph question. Neo4j would hold a copy of the order graph fed from the main store, not be the main store.

## Side by side

| | MySQL (Portfolios 1 to 3) | MongoDB (this portfolio) | Redis | Cassandra | Neo4j |
|---|---|---|---|---|---|
| Best MarketLane use | Orders, payments, stock: the record of truth | Catalogue and order documents | Cart, session, flash-sale counter | Delivery event stream | Recommendations |
| Schema | Fixed, enforced | Flexible, optional validation | None | Fixed per table, query-first | Flexible |
| Joins | Yes | `$lookup`, used sparingly | No | No | Relationships are the point |
| Transactions | Yes, any rows | Single document always; multi-document needs a replica set | Single command | Single partition | Yes |
| Integrity | FK, CHECK, UNIQUE enforced | UNIQUE enforced; the rest is on the app | On the app | On the app | Constraints on properties |
| Attribute filter (Q6) | Self-join | Filter with wildcard index | Not possible | Second table | Pattern match |
| Scales by | Bigger server, read replicas | Sharding by key (Portfolio 5) | Clustering by key | Adding nodes | Bigger server, read replicas |

## What I would actually run

MySQL stays as the record of truth for orders, payments and stock, because it enforces the rules from Portfolio 1 and gives the transactions from Portfolio 3 without conditions. MongoDB holds the catalogue, because attributes are what it is good at, and serves a read copy of orders built for the order page and the tracking page. Redis holds carts and sessions. Cassandra and Neo4j I would add only when the delivery feed or the recommendation feature became big enough to justify another system to look after.

The point of this portfolio is not that MongoDB replaces MySQL. It is that the attribute problem I flagged in Portfolio 1 has a natural answer in a document, and that each part of MarketLane has a shape, and the right store is the one built for that shape.
