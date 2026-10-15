# Portfolio 1: Database Design and Modelling

This folder holds the database design and modelling for MarketLane, a small Nigerian online shop. The goal was to model everything the shop needs to run day to day: customers and their delivery addresses, a product catalogue with categories and stock levels, orders and the items on them, payments, and courier deliveries that can be tracked step by step. The database is written for MySQL using the InnoDB engine.

## What is in this folder

`e-commerce-database.sql` creates the `marketlane` database and all eleven of its tables. Running it drops any existing copy first, so it always gives you a clean start.

`seed-data.sql` fills the tables with a small set of realistic sample data: five customers in different Nigerian cities, eight products across five categories, five orders in different stages (delivered, shipped, paid, pending and cancelled), along with their payments and deliveries.

`test-constraint.sql` contains twelve tests that try to break the rules built into the schema, such as inserting a duplicate email, setting stock below zero or deleting a customer who still has orders. Each test is commented with the error MySQL is expected to return, and the last two check that valid deletes still work and that the failed statements left the data untouched.

`normalisation.md` explains how the tables were arrived at. It starts from a single flat order record, takes it through first, second and third normal form, checks the result against Boyce-Codd normal form, and explains the two places where data is deliberately duplicated.

`er-diagram.png` is the entity-relationship diagram for the database, and `schema-screenshot.png` shows the schema as created in MySQL.

![ER diagram](https://github.com/JacqlineCPE/advance-database-portfolio/blob/main/portfolio-1-database-design/er-diagram.png)

## How the database is organised

A customer can have several saved addresses, and each order is linked to the customer who placed it and the address it is going to. Every order is made up of order items, one per product, and each item stores the price paid at the time of sale so that old orders stay correct when prices change later.

Products belong to a category, and categories can sit inside a parent category, which is how Phones ends up under Electronics. Details that only apply to some products, such as storage size for phones or shirt size for clothing, are kept in a separate product attribute table instead of adding mostly empty columns to every product. Stock is kept in its own inventory table with a reorder level, because it changes far more often than the rest of the product information.

An order can have more than one payment, which allows for a failed attempt followed by a successful one. Each order can have at most one delivery, and every change in that delivery's status is recorded in a history table with a time and location, so the full journey of a parcel can be shown to the customer.

## Rules the database enforces

The schema protects the data with constraints rather than relying on the application to get things right. Emails, product SKUs, payment references and tracking numbers must all be unique. Prices, stock levels and payment amounts cannot be negative, and an order line must have a quantity of at least one. Order, payment and delivery statuses are limited to a fixed list of values. Foreign keys stop you from creating an order for a customer who does not exist, or from deleting a customer, product or address that is still referenced by an order, while removing a customer with no orders cleanly removes their addresses along with them.

![Schema screenshot](https://github.com/JacqlineCPE/advance-database-portfolio/blob/main/portfolio-1-database-design/schema-screenshot.png)
