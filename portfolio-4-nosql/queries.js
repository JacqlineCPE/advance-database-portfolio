// MarketLane: the Portfolio 2 questions, asked of the document model
// Run in the Compass shell: load("C:/path/to/queries.js"), or paste one block at a time.
// Each block is numbered to match the SQL query it replaces in portfolio-2/queries.sql.

db = db.getSiblingDB("marketlane");

// ------------------------------------------------------------
// Q1: Order history for one customer (newest first)
// SQL needed a join to count items. Here the items are in the document.
// ------------------------------------------------------------
print("\n--- Q1: order history for customer 1 ---");
db.orders.find(
    { "customer.id": 1 },
    { order_date: 1, status: 1, total_amount: 1, item_count: { $size: "$items" } }
).sort({ order_date: -1 }).forEach(printjson);


// ------------------------------------------------------------
// Q2: Monthly order count and revenue (aggregation pipeline)
// ------------------------------------------------------------
print("\n--- Q2: monthly revenue ---");
db.orders.aggregate([
    { $match: { status: { $in: ["paid", "shipped", "delivered"] } } },
    { $group: {
        _id: { $dateToString: { format: "%Y-%m", date: "$order_date" } },
        orders: { $sum: 1 },
        revenue: { $sum: "$total_amount" }
    } },
    { $sort: { _id: 1 } }
]).forEach(printjson);


// ------------------------------------------------------------
// Q3: Top products by units sold
// $unwind turns each order into one row per item, then $group adds them up.
// ------------------------------------------------------------
print("\n--- Q3: top products by units sold ---");
db.orders.aggregate([
    { $match: { status: "delivered" } },
    { $unwind: "$items" },
    { $group: {
        _id: "$items.product_id",
        name: { $first: "$items.name" },
        units_sold: { $sum: "$items.quantity" },
        revenue: { $sum: "$items.line_total" }
    } },
    { $sort: { units_sold: -1 } },
    { $limit: 10 }
]).forEach(printjson);


// ------------------------------------------------------------
// Q4: Products at or below reorder level
// $expr lets one field be compared to another in the same document.
// ------------------------------------------------------------
print("\n--- Q4: restock list ---");
db.products.find(
    { is_active: true, $expr: { $lte: ["$stock.quantity_on_hand", "$stock.reorder_level"] } },
    { sku: 1, name: 1, stock: 1 }
).forEach(printjson);


// ------------------------------------------------------------
// Q5: Latest status of every in-transit delivery
// The history is embedded in time order, so the latest entry is the last one.
// No subquery, no join: $arrayElemAt with -1 reads the last element.
// ------------------------------------------------------------
print("\n--- Q5: latest status of in-transit deliveries ---");
db.orders.aggregate([
    { $match: { "delivery.status": "in_transit" } },
    { $project: {
        tracking_number: "$delivery.tracking_number",
        courier: "$delivery.courier",
        latest: { $arrayElemAt: ["$delivery.history", -1] }
    } }
]).forEach(printjson);


// ------------------------------------------------------------
// Q6: Products that are Black AND 128GB
// In SQL this was a self-join on product_attribute. Here it is a plain filter.
// ------------------------------------------------------------
print("\n--- Q6: black, 128GB products ---");
db.products.find(
    { "attributes.colour": "Black", "attributes.storage": "128GB", is_active: true },
    { sku: 1, name: 1, unit_price: 1, attributes: 1 }
).sort({ unit_price: 1 }).forEach(printjson);


// ------------------------------------------------------------
// Q7: Top customers by spend in each state
// Group by customer, then collect per state and slice the top 3.
// ------------------------------------------------------------
print("\n--- Q7: top spenders per state ---");
db.orders.aggregate([
    { $match: { status: "delivered" } },
    { $group: {
        _id: { state: "$delivery_address.state", customer: "$customer.full_name" },
        total_spent: { $sum: "$total_amount" }
    } },
    { $sort: { "_id.state": 1, total_spent: -1 } },
    { $group: {
        _id: "$_id.state",
        top: { $push: { customer: "$_id.customer", total_spent: "$total_spent" } }
    } },
    { $project: { top: { $slice: ["$top", 3] } } },
    { $sort: { _id: 1 } }
]).forEach(printjson);


// ------------------------------------------------------------
// Q8: Pending orders with no successful payment
// $not + $elemMatch: no element of the payments array has status "successful".
// ------------------------------------------------------------
print("\n--- Q8: pending orders with no successful payment ---");
db.orders.find(
    { status: "pending", payments: { $not: { $elemMatch: { status: "successful" } } } },
    { order_date: 1, total_amount: 1, "customer.email": 1, "payments.status": 1 }
).sort({ order_date: 1 }).forEach(printjson);


// ------------------------------------------------------------
// W1: Sell one unit of product 2, but only if there is stock.
// This is the Portfolio 3 lost-update problem solved in one statement:
// the filter and the $inc happen together under the document lock, so two
// customers buying the last unit cannot both succeed.
// ------------------------------------------------------------
print("\n--- W1: atomic stock decrement on product 2 ---");
printjson(db.products.findOneAndUpdate(
    { _id: 2, "stock.quantity_on_hand": { $gte: 1 } },
    { $inc: { "stock.quantity_on_hand": -1 } },
    { returnDocument: "after", projection: { name: 1, stock: 1 } }
));

print("--- W1 again on product 6 (stock 0): returns null, nothing changed ---");
printjson(db.products.findOneAndUpdate(
    { _id: 6, "stock.quantity_on_hand": { $gte: 1 } },
    { $inc: { "stock.quantity_on_hand": -1 } },
    { returnDocument: "after", projection: { name: 1, stock: 1 } }
));


// ------------------------------------------------------------
// W2: Record a delivery status change
// $push appends to the embedded history; $set updates the current status.
// One write, one document, no second table.
// ------------------------------------------------------------
print("\n--- W2: order 2 delivered ---");
db.orders.updateOne(
    { _id: 2 },
    { $set: { "delivery.status": "delivered", "delivery.delivered_at": new Date("2026-10-07T11:30:00Z"), status: "delivered" },
      $push: { "delivery.history": { status: "delivered", location: "23 Allen Avenue", recorded_at: new Date("2026-10-07T11:30:00Z") } } }
);
printjson(db.orders.findOne({ _id: 2 }, { status: 1, "delivery.status": 1, "delivery.history": 1 }));


// ------------------------------------------------------------
// L1: A join, for when you need one. $lookup pulls the current product
// document into each order item, e.g. to compare the price paid with today's price.
// ------------------------------------------------------------
print("\n--- L1: price paid vs current price (a $lookup) ---");
db.orders.aggregate([
    { $match: { _id: 1 } },
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.product_id", foreignField: "_id", as: "product" } },
    { $unwind: "$product" },
    { $project: {
        item: "$items.name",
        price_paid: "$items.unit_price",
        price_now: "$product.unit_price",
        stock_now: "$product.stock.quantity_on_hand"
    } }
]).forEach(printjson);


// ------------------------------------------------------------
// X1: Show that Q6 uses the wildcard index
// ------------------------------------------------------------
print("\n--- X1: explain for Q6 ---");
const plan = db.products.find({ "attributes.colour": "Black", "attributes.storage": "128GB" }).explain("executionStats");
print("winning plan stage: " + JSON.stringify(plan.queryPlanner.winningPlan.inputStage?.stage || plan.queryPlanner.winningPlan.stage));
print("index used:         " + JSON.stringify(plan.queryPlanner.winningPlan.inputStage?.indexName));
print("docs examined:      " + plan.executionStats.totalDocsExamined + " of " + db.products.countDocuments());
