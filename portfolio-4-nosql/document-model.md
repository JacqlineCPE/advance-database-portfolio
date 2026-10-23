# The document model

This is how I turned the eleven MySQL tables from Portfolio 1 into four MongoDB collections, and why each piece ended up where it did.

## From tables to collections

| MySQL table | Where it went | Why |
|---|---|---|
| `product` | `products` collection, one document each | The thing customers browse |
| `product_attribute` | Embedded in `products` as an `attributes` object | The whole reason for this portfolio; see below |
| `inventory` | Embedded in `products` as a `stock` object | One row per product, always read with the product |
| `category` | Small `categories` collection; name also copied into each product | Keeps the parent/child tree; the copy saves a lookup on every product page |
| `customer` | `customers` collection | One document per account |
| `address` | Embedded in `customers` as an `addresses` array | A customer has a few, they belong to nobody else |
| `customer_order` | `orders` collection, one document each | The main record |
| `order_item` | Embedded in `orders` as an `items` array | An item has no meaning without its order |
| `payment` | Embedded in `orders` as a `payments` array | A handful per order, same lifecycle |
| `delivery` | Embedded in `orders` as a `delivery` object | One per order |
| `delivery_status_history` | Embedded inside `delivery` as a `history` array | A few entries per delivery, always read together |

Eleven tables became four collections. The `orders` document alone replaces six tables and the two joins to customer and address.

## A product

```json
{
  "_id": 1,
  "sku": "SKU-PH-001",
  "name": "Smartphone X10 128GB",
  "category": { "id": 2, "name": "Phones" },
  "unit_price": 185000,
  "is_active": true,
  "attributes": { "colour": "Black", "ram": "6GB", "storage": "128GB" },
  "stock": { "quantity_on_hand": 25, "reorder_level": 5 }
}
```

In MySQL the three attributes were three rows in `product_attribute`, and asking for "black and 128GB" meant joining that table to itself. Here they are three fields in an object, and the question is `{ "attributes.colour": "Black", "attributes.storage": "128GB" }`. A shirt's document has `size` and `material` instead, and nothing is NULL because fields that do not apply are simply not there.

I kept attributes as an object with named keys rather than an array of name/value pairs. The object form reads better, filters more simply, and a single wildcard index on `attributes.$**` covers every attribute name present or added later.

## An order

```json
{
  "_id": 2,
  "customer": { "id": 2, "full_name": "Tunde Bakare", "email": "tunde.bakare@example.com" },
  "delivery_address": { "street": "23 Allen Avenue", "city": "Ikeja", "state": "Lagos" },
  "order_date": "2026-10-05T14:40:00Z",
  "status": "shipped",
  "total_amount": 39500,
  "items": [
    { "product_id": 5, "sku": "SKU-FA-005", "name": "Ankara Print Shirt", "quantity": 2, "unit_price": 12000, "line_total": 24000 },
    { "product_id": 6, "sku": "SKU-FA-006", "name": "Leather Sandals", "quantity": 1, "unit_price": 15500, "line_total": 15500 }
  ],
  "payments": [
    { "amount": 39500, "method": "bank_transfer", "status": "failed", "reference": "PAY-20261005-0002" },
    { "amount": 39500, "method": "bank_transfer", "status": "successful", "reference": "PAY-20261005-0003", "paid_at": "2026-10-05T15:02:45Z" }
  ],
  "delivery": {
    "courier": "Kwik Delivery", "tracking_number": "TRK-ML-000002", "status": "in_transit",
    "history": [
      { "status": "pending", "location": "Lagos warehouse", "recorded_at": "2026-10-05T15:05:00Z" },
      { "status": "dispatched", "location": "Ikeja hub", "recorded_at": "2026-10-06T09:00:00Z" },
      { "status": "in_transit", "location": "Allen Avenue route", "recorded_at": "2026-10-06T13:45:00Z" }
    ]
  }
}
```

Everything the order page, the receipt and the tracking page need is in one read.

## Embed or reference

The rule I used: embed when the child belongs to exactly one parent, is read with it, and there will never be many of it. Reference when the child has a life of its own or the list could grow without limit.

**Embedded.** Attributes, stock, addresses, items, payments, delivery and its history. All of these are owned by one parent and are small. A delivery passes through four or five statuses, not four thousand.

**Referenced.** `items.product_id` points back to `products`, and `customer.id` points back to `customers`. Products and customers exist on their own, are shared across many orders, and get updated independently. Copying the whole product into every order would mean a price change touching thousands of documents.

**Copied on purpose.** The order carries the customer's name and email, the delivery address, and each item's name, SKU and price at the time of sale. This is the same decision as `order_item.unit_price` in Portfolio 1: an order is a record of what happened, and it must not change when the customer moves house or the product is repriced. The copy is the history. The category name is also copied into each product so a product page needs no second read; if a category is renamed, the products in it get a one-off `updateMany`.

**Not copied.** The current stock level lives only in `products`. An order holds the quantity bought, never the stock that was left, because that number changes constantly and an order has no business knowing it.

## What MongoDB does not do for me

MySQL enforced a lot in Portfolio 1 that MongoDB will not enforce on its own.

There are no foreign keys. Nothing stops an order being inserted with a `product_id` that does not exist. The application has to check, or a `$lookup` at read time will come back empty.

There are no CHECK constraints by default. `stock.quantity_on_hand` can go negative if a write lets it. The write in `queries.js` guards against this by putting the condition in the filter: `{ "stock.quantity_on_hand": { $gte: 1 } }` with `$inc: -1`. The filter and the update are one atomic operation on one document, which is MongoDB's version of the row lock from Portfolio 3. MongoDB does have JSON Schema validation that can be attached to a collection to enforce types and ranges, and in production I would turn it on for `products` and `orders`.

There is no `ENUM`. `status` is a string and a typo would be accepted. Again, schema validation can restrict it to a list.

Uniqueness still works: the unique indexes on `sku` and `email` in `indexes.js` do the same job as the `UNIQUE` keys in Portfolio 1.

## Indexes

`indexes.js` creates eight. Three are the same idea as Portfolio 2: a compound index on `orders (status, order_date)` for the status-and-date queries, and single-field ones for the dashboard and the customer's order list. Two are new kinds. The wildcard index on `attributes.$**` indexes every attribute of every product without the names being known in advance, which has no equivalent in MySQL. And the index on `items.product_id` is a multikey index: one entry per element of the array, so "which orders contain product 6" is an index lookup even though the product IDs are inside an array.
