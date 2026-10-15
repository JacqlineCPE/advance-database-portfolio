-- MarketLane e-commerce database

DROP DATABASE IF EXISTS marketlane;

CREATE DATABASE marketlane;
USE marketlane;

CREATE TABLE customer (
    customer_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    full_name     VARCHAR(100)  NOT NULL,
    email         VARCHAR(150)  NOT NULL,
    phone         VARCHAR(20)   NOT NULL,
    created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (customer_id),
    UNIQUE KEY uq_customer_email (email)
) ENGINE=InnoDB;

CREATE TABLE address (
    address_id    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    customer_id   INT UNSIGNED  NOT NULL,
    street        VARCHAR(200)  NOT NULL,
    city          VARCHAR(80)   NOT NULL,
    state         VARCHAR(50)   NOT NULL,
    is_default    BOOLEAN       NOT NULL DEFAULT FALSE,
    PRIMARY KEY (address_id),
    CONSTRAINT fk_address_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- parent_category_id is NULL for top-level categories
CREATE TABLE category (
    category_id         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    name                VARCHAR(80)   NOT NULL,
    parent_category_id  INT UNSIGNED  NULL,
    PRIMARY KEY (category_id),
    UNIQUE KEY uq_category_name (name),
    CONSTRAINT fk_category_parent
        FOREIGN KEY (parent_category_id) REFERENCES category (category_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE product (
    product_id    INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    category_id   INT UNSIGNED   NOT NULL,
    sku           VARCHAR(40)    NOT NULL,
    name          VARCHAR(150)   NOT NULL,
    description   TEXT           NULL,
    unit_price    DECIMAL(12,2)  NOT NULL,
    is_active     BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (product_id),
    UNIQUE KEY uq_product_sku (sku),
    CONSTRAINT fk_product_category
        FOREIGN KEY (category_id) REFERENCES category (category_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_product_price CHECK (unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE product_attribute (
    attribute_id     INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    product_id       INT UNSIGNED  NOT NULL,
    attribute_name   VARCHAR(50)   NOT NULL,
    attribute_value  VARCHAR(100)  NOT NULL,
    PRIMARY KEY (attribute_id),
    UNIQUE KEY uq_product_attribute (product_id, attribute_name),
    CONSTRAINT fk_attribute_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- one row per product; product_id is both PK and FK
CREATE TABLE inventory (
    product_id        INT UNSIGNED  NOT NULL,
    quantity_on_hand  INT           NOT NULL DEFAULT 0,
    reorder_level     INT           NOT NULL DEFAULT 5,
    updated_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (product_id),
    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_inventory_qty CHECK (quantity_on_hand >= 0),
    CONSTRAINT chk_inventory_reorder CHECK (reorder_level >= 0)
) ENGINE=InnoDB;

CREATE TABLE customer_order (
    order_id      INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    customer_id   INT UNSIGNED   NOT NULL,
    address_id    INT UNSIGNED   NOT NULL,
    order_date    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status        ENUM('pending','paid','shipped','delivered','cancelled') NOT NULL DEFAULT 'pending',
    total_amount  DECIMAL(12,2)  NOT NULL DEFAULT 0.00,
    PRIMARY KEY (order_id),
    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id) REFERENCES customer (customer_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_order_address
        FOREIGN KEY (address_id) REFERENCES address (address_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_order_total CHECK (total_amount >= 0)
) ENGINE=InnoDB;

-- unit_price is copied from product at time of sale so history survives price changes
CREATE TABLE order_item (
    order_item_id  INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    order_id       INT UNSIGNED   NOT NULL,
    product_id     INT UNSIGNED   NOT NULL,
    quantity       INT            NOT NULL,
    unit_price     DECIMAL(12,2)  NOT NULL,
    PRIMARY KEY (order_item_id),
    UNIQUE KEY uq_order_product (order_id, product_id),
    CONSTRAINT fk_item_order
        FOREIGN KEY (order_id) REFERENCES customer_order (order_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_item_product
        FOREIGN KEY (product_id) REFERENCES product (product_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_item_qty CHECK (quantity > 0),
    CONSTRAINT chk_item_price CHECK (unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE payment (
    payment_id   INT UNSIGNED   NOT NULL AUTO_INCREMENT,
    order_id     INT UNSIGNED   NOT NULL,
    amount       DECIMAL(12,2)  NOT NULL,
    method       ENUM('card','bank_transfer','pay_on_delivery') NOT NULL,
    status       ENUM('initiated','successful','failed','refunded') NOT NULL DEFAULT 'initiated',
    reference    VARCHAR(60)    NOT NULL,
    paid_at      DATETIME       NULL,
    PRIMARY KEY (payment_id),
    UNIQUE KEY uq_payment_reference (reference),
    CONSTRAINT fk_payment_order
        FOREIGN KEY (order_id) REFERENCES customer_order (order_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_payment_amount CHECK (amount > 0)
) ENGINE=InnoDB;

CREATE TABLE delivery (
    delivery_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    order_id         INT UNSIGNED  NOT NULL,
    courier_name     VARCHAR(80)   NOT NULL,
    tracking_number  VARCHAR(40)   NOT NULL,
    status           ENUM('pending','dispatched','in_transit','delivered','failed') NOT NULL DEFAULT 'pending',
    dispatched_at    DATETIME      NULL,
    delivered_at     DATETIME      NULL,
    PRIMARY KEY (delivery_id),
    UNIQUE KEY uq_delivery_order (order_id),
    UNIQUE KEY uq_delivery_tracking (tracking_number),
    CONSTRAINT fk_delivery_order
        FOREIGN KEY (order_id) REFERENCES customer_order (order_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE delivery_status_history (
    history_id   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    delivery_id  INT UNSIGNED  NOT NULL,
    status       ENUM('pending','dispatched','in_transit','delivered','failed') NOT NULL,
    location     VARCHAR(120)  NULL,
    recorded_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (history_id),
    CONSTRAINT fk_history_delivery
        FOREIGN KEY (delivery_id) REFERENCES delivery (delivery_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;