
-- Test 1: duplicate email (UNIQUE uq_customer_email)
-- Expected: ERROR 1062 Duplicate entry
INSERT INTO customer (full_name, email, phone)
VALUES ('Someone Else', 'adaeze.okonkwo@example.com', '08000000000');

-- Test 2: duplicate SKU (UNIQUE uq_product_sku)
-- Expected: ERROR 1062 Duplicate entry
INSERT INTO product (category_id, sku, name, unit_price)
VALUES (1, 'SKU-PH-001', 'Duplicate Phone', 100000.00);

-- Test 3: negative stock (CHECK chk_inventory_qty)
-- Expected: ERROR 3819 Check constraint violated
UPDATE inventory SET quantity_on_hand = -1 WHERE product_id = 1;

-- Test 4: negative price (CHECK chk_product_price)
-- Expected: ERROR 3819 Check constraint violated
INSERT INTO product (category_id, sku, name, unit_price)
VALUES (1, 'SKU-XX-999', 'Free Phone', -5.00);

-- Test 5: zero quantity on an order line (CHECK chk_item_qty)
-- Expected: ERROR 3819 Check constraint violated
INSERT INTO order_item (order_id, product_id, quantity, unit_price)
VALUES (1, 4, 0, 32000.00);

-- Test 6: order for a customer that does not exist (FK fk_order_customer)
-- Expected: ERROR 1452 foreign key constraint fails
INSERT INTO customer_order (customer_id, address_id) VALUES (999, 1);

-- Test 7: invalid status value (ENUM)
-- Expected: ERROR 1265 Data truncated for column 'status'
UPDATE customer_order SET status = 'lost' WHERE order_id = 1;

-- Test 8: delete a customer who has orders (ON DELETE RESTRICT)
-- Expected: ERROR 1451 foreign key constraint fails
-- The error names fk_order_address, not fk_order_customer: MySQL first tries to
-- cascade the delete to her addresses, and that is blocked because an order
-- references the address. Either way the customer cannot be deleted.
DELETE FROM customer WHERE customer_id = 1;

-- Test 9: second delivery for the same order (UNIQUE uq_delivery_order)
-- Expected: ERROR 1062 Duplicate entry
INSERT INTO delivery (order_id, courier_name, tracking_number)
VALUES (1, 'Another Courier', 'TRK-ML-000099');

-- Test 10: same attribute twice on one product (UNIQUE uq_product_attribute)
-- Expected: ERROR 1062 Duplicate entry
INSERT INTO product_attribute (product_id, attribute_name, attribute_value)
VALUES (1, 'colour', 'Silver');

-- Test 11: ON DELETE CASCADE removes child rows (positive test)
-- Expected: succeeds. Customer 5 has no orders, so the delete is allowed
-- and address 6 disappears with her.
SELECT COUNT(*) AS addresses_before FROM address WHERE customer_id = 5;
DELETE FROM customer WHERE customer_id = 5;
SELECT COUNT(*) AS addresses_after FROM address WHERE customer_id = 5;

-- Test 12: data is unchanged by the failed statements above
-- Expected: 5 customers minus the one cascade-deleted = 4; 8 products; stock still 25
SELECT (SELECT COUNT(*) FROM customer) AS customers,
       (SELECT COUNT(*) FROM product)  AS products,
       (SELECT quantity_on_hand FROM inventory WHERE product_id = 1) AS stock_product_1;