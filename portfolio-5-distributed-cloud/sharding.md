# Sharding MarketLane

The replica set proposed in `distributed-design.md` would copy the whole database onto three servers. That protects against a server failing, but every server still holds everything and every write still goes to one primary. When the data or the write load outgrows one machine, the answer is sharding: splitting the data across several replica sets so each holds a slice. This file is the plan for doing that to MarketLane. It is a plan, not a deployment, for reasons at the end.

## What a sharded cluster is

```
                    application / Compass
                             |
                          mongos            <- query router, knows which shard has what
                             |
          +------------------+------------------+
          |                  |                  |
      shard A            shard B            shard C         <- each one a 3-node replica set
   (orders: part)     (orders: part)     (orders: part)
          |                  |                  |
          +------------------+------------------+
                             |
                     config servers            <- a replica set holding the map of chunks to shards
```

A collection is split into chunks by a shard key. The config servers record which chunk lives on which shard. `mongos` reads that map and sends each query to the shard or shards that can answer it. A query that includes the shard key goes to one shard; one that does not goes to all of them and the results are merged, which is called scatter-gather and is what you want to avoid.

## Choosing shard keys

The shard key is the decision that matters, and it cannot be changed cheaply afterwards. It should spread writes evenly and let the common queries go to one shard.

**orders.** This is the collection that grows. Three candidates:

| Shard key | Writes spread? | Q1 (one customer's orders) | Q2 (monthly revenue) | Verdict |
|---|---|---|---|---|
| `{ order_date: 1 }` | No. New orders all have today's date, so they all land on the one shard holding the latest range. That shard takes every write while the others idle. | Scatter-gather | One shard per month | Rejected: the hot-shard problem |
| `{ "customer.id": "hashed" }` | Yes. Hashing scatters consecutive IDs across all shards. | One shard | Scatter-gather | Chosen |
| `{ "delivery_address.state": 1, order_date: 1 }` | Uneven: Lagos would get far more orders than Kaduna. | Scatter-gather | Scatter-gather, but each shard does a range scan | Useful with zones, see below |

I would shard `orders` on `{ "customer.id": "hashed" }`. The customer-facing queries, order history and tracking, all include the customer and go to one shard. The reporting queries (Q2, Q3, Q7) go to every shard, but they already scan every order even on one server, and running the scan in parallel on three shards is faster, not slower. Hashing spreads different customers across the shards, so new orders from many customers arrive on all shards at once instead of piling up on one. All of one customer's orders still hash to the same value and stay together, which is what the order history query wants. A single customer who ordered far more than everyone else would be a hot spot on one shard, but no retail customer orders enough for that to matter.

**products.** 5,000 documents, read constantly, written rarely. Too small to shard. It stays on the primary shard as an ordinary collection, and every `mongos` can reach it. The same goes for `customers` and `categories`.

**Zones.** MarketLane is Nigerian, and if it grew to serve West Africa the orders could be pinned to shards by region: a Lagos shard, an Abuja shard, an Accra shard, each physically near its customers. That needs the region in the shard key, which is where the `state` key from the table comes in: `{ "delivery_address.state": 1, "customer.id": 1 }` with a zone range per state. Reads and writes for Lagos customers stay in Lagos. This is also how data-residency rules get met, if a country requires its citizens' data to stay inside its borders.

## The commands

On a running cluster, through `mongos`:

```javascript
sh.enableSharding("marketlane")

// hash the customer id so writes spread evenly
sh.shardCollection("marketlane.orders", { "customer.id": "hashed" })

// products, customers and categories stay unsharded on the primary shard

sh.status()        // shows chunks per shard and the balancer state
```

After this the balancer moves chunks between shards in the background to keep them even, and the application connects to `mongos` exactly as it connected to the replica set before. Nothing in `queries.js` from Portfolio 4 changes.

## What sharding costs

Transactions that touch two shards are slower than ones inside a shard, because they need a two-phase commit across them. A transaction that takes stock off a product and inserts an order would span the primary shard and an orders shard. Unique indexes only work if the shard key is a prefix of them, so `uq_sku` on products is fine (unsharded) but a unique index on `orders.reference` would need the shard key in it. And the cluster needs at least ten processes to be safe: three config servers, three per shard, and a `mongos` or two.

## Why I did not deploy it

A minimum sharded cluster for a demo is one config replica set, two one-node shards and a `mongos`: six MongoDB processes at least. It would run on a laptop, but with 23 documents it would show chunks being created and nothing else, because the balancer does not move anything until a chunk is large enough to split. Sharding is the plan for when `orders` reaches hundreds of millions of documents, and the plan above is what I would do.
