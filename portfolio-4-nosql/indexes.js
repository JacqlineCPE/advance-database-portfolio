// MarketLane: indexes for the document model
// Run in the Compass shell after importing the four JSON files:
//   load("C:/path/to/indexes.js")      (or paste the lines in one at a time)

db = db.getSiblingDB("marketlane");

// Products are looked up by SKU, and SKUs must not repeat
db.products.createIndex({ sku: 1 }, { unique: true, name: "uq_sku" });

// A wildcard index covers every attribute without knowing their names in advance.
// This is what makes "colour = Black AND storage = 128GB" fast when attributes differ per product.
db.products.createIndex({ "attributes.$**": 1 }, { name: "idx_attributes" });

// Restock list: products at or below reorder level
db.products.createIndex({ "stock.quantity_on_hand": 1 }, { name: "idx_stock" });

// Customers are found by email at login, and emails must not repeat
db.customers.createIndex({ email: 1 }, { unique: true, name: "uq_email" });

// A customer's order history, newest first
db.orders.createIndex({ "customer.id": 1, order_date: -1 }, { name: "idx_customer_orders" });

// Same shape as idx_order_status_date_total from Portfolio 2: status first, then date
db.orders.createIndex({ status: 1, order_date: 1 }, { name: "idx_status_date" });

// "Which orders contain product X" reaches into the items array (a multikey index)
db.orders.createIndex({ "items.product_id": 1 }, { name: "idx_items_product" });

// Deliveries still moving, for the logistics dashboard
db.orders.createIndex({ "delivery.status": 1 }, { name: "idx_delivery_status" });

print("products:  " + JSON.stringify(db.products.getIndexes().map(i => i.name)));
print("customers: " + JSON.stringify(db.customers.getIndexes().map(i => i.name)));
print("orders:    " + JSON.stringify(db.orders.getIndexes().map(i => i.name)));
