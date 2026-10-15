
INSERT INTO category (category_id, name, parent_category_id) VALUES
(1, 'Electronics', NULL),
(2, 'Phones', 1),
(3, 'Fashion', NULL),
(4, 'Home & Kitchen', NULL),
(5, 'Groceries', NULL);

INSERT INTO customer (customer_id, full_name, email, phone) VALUES
(1, 'Adaeze Okonkwo',  'adaeze.okonkwo@example.com',  '08031112222'),
(2, 'Tunde Bakare',    'tunde.bakare@example.com',    '08052223333'),
(3, 'Fatima Abdullahi','fatima.abdullahi@example.com','07063334444'),
(4, 'Emeka Nwosu',     'emeka.nwosu@example.com',     '09014445555'),
(5, 'Ngozi Eze',       'ngozi.eze@example.com',       '08125556666');

INSERT INTO address (address_id, customer_id, street, city, state, is_default) VALUES
(1, 1, '12 Sapele Road',          'Benin City',   'Edo',    TRUE),
(2, 1, '4 Ugbowo Housing Estate', 'Benin City',   'Edo',    FALSE),
(3, 2, '23 Allen Avenue',         'Ikeja',        'Lagos',  TRUE),
(4, 3, '7 Ahmadu Bello Way',      'Kaduna',       'Kaduna', TRUE),
(5, 4, '15 Okpara Avenue',        'Enugu',        'Enugu',  TRUE),
(6, 5, '9 Aba Road',              'Port Harcourt','Rivers', TRUE);

INSERT INTO product (product_id, category_id, sku, name, description, unit_price) VALUES
(1, 2, 'SKU-PH-001', 'Smartphone X10 128GB',       '6.6-inch display, 128GB storage, dual SIM', 185000.00),
(2, 2, 'SKU-PH-002', 'Smartphone Pro 256GB',       '6.7-inch AMOLED, 256GB storage, 5G',        245000.00),
(3, 1, 'SKU-EL-003', 'Power Bank 20000mAh',        'Fast charging, dual USB output',             18500.00),
(4, 1, 'SKU-EL-004', 'Bluetooth Speaker',          'Portable, 12-hour battery, waterproof',      32000.00),
(5, 3, 'SKU-FA-005', 'Ankara Print Shirt',         '100% cotton, short sleeve',                  12000.00),
(6, 3, 'SKU-FA-006', 'Leather Sandals',            'Handmade, genuine leather',                  15500.00),
(7, 4, 'SKU-HM-007', 'Non-stick Frying Pan 28cm',  'Aluminium body, bakelite handle',             9800.00),
(8, 5, 'SKU-GR-008', 'Parboiled Rice 10kg',        'Long grain, stone-free',                     26000.00);

INSERT INTO product_attribute (product_id, attribute_name, attribute_value) VALUES
(1, 'colour',   'Black'),
(1, 'storage',  '128GB'),
(1, 'ram',      '6GB'),
(2, 'colour',   'Midnight Blue'),
(2, 'storage',  '256GB'),
(2, 'ram',      '8GB'),
(3, 'capacity', '20000mAh'),
(4, 'colour',   'Red'),
(5, 'size',     'L'),
(5, 'material', 'Cotton'),
(6, 'size',     '43'),
(6, 'colour',   'Brown'),
(7, 'diameter', '28cm'),
(8, 'weight',   '10kg');

INSERT INTO inventory (product_id, quantity_on_hand, reorder_level) VALUES
(1, 25, 5),
(2,  3, 5),
(3, 60, 10),
(4, 14, 5),
(5, 40, 10),
(6,  0, 5),
(7, 22, 5),
(8, 80, 20);

INSERT INTO customer_order (order_id, customer_id, address_id, order_date, status, total_amount) VALUES
(1, 1, 1, '2026-10-01 09:15:00', 'delivered', 222000.00),
(2, 2, 3, '2026-10-05 14:40:00', 'shipped',    39500.00),
(3, 3, 4, '2026-10-10 11:05:00', 'paid',      245000.00),
(4, 4, 5, '2026-10-12 18:30:00', 'pending',    35800.00),
(5, 1, 2, '2026-10-13 08:00:00', 'cancelled',  32000.00);

INSERT INTO order_item (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 185000.00),
(1, 3, 2,  18500.00),
(2, 5, 2,  12000.00),
(2, 6, 1,  15500.00),
(3, 2, 1, 245000.00),
(4, 7, 1,   9800.00),
(4, 8, 1,  26000.00),
(5, 4, 1,  32000.00);

INSERT INTO payment (order_id, amount, method, status, reference, paid_at) VALUES
(1, 222000.00, 'card',            'successful', 'PAY-20261001-0001', '2026-10-01 09:16:10'),
(2,  39500.00, 'bank_transfer',   'failed',     'PAY-20261005-0002', NULL),
(2,  39500.00, 'bank_transfer',   'successful', 'PAY-20261005-0003', '2026-10-05 15:02:45'),
(3, 245000.00, 'card',            'successful', 'PAY-20261010-0004', '2026-10-10 11:06:00'),
(4,  35800.00, 'pay_on_delivery', 'initiated',  'PAY-20261012-0005', NULL),
(5,  32000.00, 'card',            'refunded',   'PAY-20261013-0006', '2026-10-13 08:01:30');

INSERT INTO delivery (delivery_id, order_id, courier_name, tracking_number, status, dispatched_at, delivered_at) VALUES
(1, 1, 'GIG Logistics', 'TRK-ML-000001', 'delivered',  '2026-10-02 07:30:00', '2026-10-03 16:20:00'),
(2, 2, 'Kwik Delivery', 'TRK-ML-000002', 'in_transit', '2026-10-06 09:00:00', NULL);

INSERT INTO delivery_status_history (delivery_id, status, location, recorded_at) VALUES
(1, 'pending',    'Benin City warehouse', '2026-10-01 09:20:00'),
(1, 'dispatched', 'Benin City hub',       '2026-10-02 07:30:00'),
(1, 'in_transit', 'Ring Road sorting',    '2026-10-02 14:10:00'),
(1, 'delivered',  '12 Sapele Road',       '2026-10-03 16:20:00'),
(2, 'pending',    'Lagos warehouse',      '2026-10-05 15:05:00'),
(2, 'dispatched', 'Ikeja hub',            '2026-10-06 09:00:00'),
(2, 'in_transit', 'Allen Avenue route',   '2026-10-06 13:45:00');