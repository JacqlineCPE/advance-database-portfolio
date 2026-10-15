# Normalisation

This file explains how I arrived at the MarketLane tables. I started with one flat record holding everything about an order, then split it up one normal form at a time. At the end I explain two places where I kept duplicate data on purpose.

## Where I started

If MarketLane kept its records the way a paper order form works, one order would be a single record with everything on it. Here is order 1 from the seed data written that way:

```
order_id:        1
order_date:      2026-10-01
customer_name:   Adaeze Okonkwo
customer_email:  adaeze.okonkwo@example.com
customer_phone:  08031112222
delivery:        12 Sapele Road, Benin City, Edo
products:        SKU-PH-001  Smartphone X10 128GB  (Phones)       x1 @ 185000
                 SKU-EL-003  Power Bank 20000mAh   (Electronics)  x2 @ 18500
payment:         card, PAY-20261001-0001
courier:         GIG Logistics, TRK-ML-000001
```

This is easy to read but bad to store. The `products` field holds two items in one place. Adaeze's name, email and phone would be copied onto every order she places, so changing her phone number means editing all of them. A product only exists if someone has ordered it, and if I delete the only order containing a product, the product disappears with it.

## First normal form

The rule for 1NF is one value per field and no repeating groups.

The products field is the problem, so I gave each product its own row. Order 1 becomes two rows, and the row is now identified by the pair (order_id, product_sku).

| order_id | order_date | customer_email | customer_name | delivery_city | product_sku | product_name | category | quantity | unit_price | payment_ref | courier |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-01 | adaeze.okonkwo@... | Adaeze Okonkwo | Benin City | SKU-PH-001 | Smartphone X10 128GB | Phones | 1 | 185000 | PAY-...0001 | GIG Logistics |
| 1 | 2026-10-01 | adaeze.okonkwo@... | Adaeze Okonkwo | Benin City | SKU-EL-003 | Power Bank 20000mAh | Electronics | 2 | 18500 | PAY-...0001 | GIG Logistics |

(Some columns are left out of the table to keep it readable: phone, street, state, payment method, tracking number.)

Every field is now a single value. The cost is that the order header, the date, customer, address, payment and courier, is repeated on every line of the order.

## Second normal form

2NF says every non-key column must depend on the whole key, not just part of it. The key here is (order_id, product_sku), so I checked which columns depend on which part:

- `product_name` and `category` depend only on `product_sku`. The product is the same whichever order it appears in.
- `order_date`, the customer columns, the delivery columns, the payment columns and the courier columns depend only on `order_id`. They are the same for every line of the order.
- `quantity` and `unit_price` depend on both. The quantity of the power bank on order 1 is only meaningful for that order and that product together.

Anything that depends on only part of the key moves to its own table:

```
PRODUCT     (product_sku, product_name, category)
ORDER       (order_id, order_date, customer_email, customer_name, customer_phone,
             street, city, state, payment_method, payment_ref, courier, tracking_number)
ORDER_ITEM  (order_id, product_sku, quantity, unit_price)
```

Now a product can exist before anyone orders it, and the order header is stored once instead of once per line.

## Third normal form

3NF says a non-key column must not depend on another non-key column. I looked at the ORDER and PRODUCT tables for this.

In ORDER:

- `customer_name` and `customer_phone` depend on `customer_email`, not on the order. If Adaeze changes her phone number, every order she has placed would need updating. The customer needs her own table.
- `street`, `city` and `state` describe an address. Adaeze has two addresses in the seed data and uses both. The address should be stored once and referred to from the order.
- `payment_method` depends on `payment_ref`. Also, an order can have more than one payment attempt. Order 2 in the seed data has a failed bank transfer followed by a successful one. One row per order cannot hold that, so payments need their own table.
- `courier` depends on `tracking_number`. The delivery is a separate thing that happens after the order and goes through its own stages.

In PRODUCT:

- `category` is a name. If I later want a parent category or a description, that would be repeated on every product in the category. So category becomes a table and the product points to it.

After splitting those out:

```
CUSTOMER    (customer_id, full_name, email, phone)
ADDRESS     (address_id, customer_id, street, city, state)
CATEGORY    (category_id, name, parent_category_id)
PRODUCT     (product_id, category_id, sku, name, unit_price)
ORDER       (order_id, customer_id, address_id, order_date, status)
ORDER_ITEM  (order_item_id, order_id, product_id, quantity, unit_price)
PAYMENT     (payment_id, order_id, amount, method, status, reference)
DELIVERY    (delivery_id, order_id, courier_name, tracking_number, status)
```

I switched from natural keys (email, SKU) to auto-increment integer keys at this point. Email and SKU are still unique, but as `UNIQUE` constraints rather than primary keys. That way a customer can change her email without every order row needing to change too.

## Three tables that did not come from the order form

The schema has eleven tables, not eight. The other three came from thinking about how the data is used rather than from the normal forms directly.

**product_attribute.** A phone has storage and RAM; a shirt has size and material. If I added those as columns on `product`, most of them would be NULL for most products. Instead each product has a list of name/value rows holding only the attributes it actually has.

**inventory.** Stock level could sit on `product` without breaking any normal form. I separated it because stock changes every time an order is placed, while the rest of the product row almost never changes. It also gives Portfolio 3 a single small row that two concurrent orders have to fight over.

**delivery_status_history.** A delivery goes pending, dispatched, in transit, delivered. Keeping only the current status on `delivery` loses the timeline. One row per status change keeps it, and that is what "track delivery" actually shows the customer.

## BCNF

I also checked Boyce-Codd normal form. In every table the only things that determine other columns are the primary key and the `UNIQUE` columns (email, sku, payment reference, tracking number, and the two composite unique keys). All of those are candidate keys, so there is nothing that determines another column without being a key itself. The schema is in BCNF.

## Two places where I kept duplicate data on purpose

**`order_item.unit_price`.** The current price is already on `product.unit_price`, so this looks like a copy. It is not really. It is the price the customer paid on that day. If the phone goes up to ₦195,000 next month, order 1 must still say ₦185,000. The two columns mean different things, so I do not think this breaks 3NF, but it is worth saying out loud because it looks like it does.

**`customer_order.total_amount`.** This one is genuinely redundant. It equals the sum of `quantity × unit_price` across the order's items, and I could compute it every time. I stored it because the total is shown on every order list, receipt and sales report, while it is only ever written once, when the order is placed. The risk is that it drifts out of sync with the items. To control that, the total is only written inside the same transaction that inserts the items (Portfolio 3 shows this).

This query checks the seed data for drift and returns no rows:

```sql
SELECT o.order_id, o.total_amount, SUM(i.quantity * i.unit_price) AS item_sum
FROM customer_order o
JOIN order_item i ON i.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING o.total_amount <> item_sum;
```
