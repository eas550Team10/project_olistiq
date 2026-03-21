# OlistIQ — Schema Design & 3NF Justification Report

**Course:** EAS 550 — Data Models & Query Languages (Spring 2026)  
**Team 10:** Krishna Teja Anumolu | Bandlamudi Sharan | Shreyas Aravind | Parameshwaran Arrakutti Anandhakumar  
**Dataset:** Brazilian E-Commerce Public Dataset by Olist (Kaggle, 2018)

---

## 1. Dataset Analysis & Entity Identification

The Olist dataset consists of nine interrelated CSV files capturing the full lifecycle of e-commerce transactions on the Olist marketplace from 2016 to 2018. After thoroughly analyzing the dataset, we identified the following nine core entities:

| Entity | Source CSV | Description |
|--------|-----------|-------------|
| `customers` | olist_customers_dataset.csv | Shoppers who placed orders |
| `orders` | olist_orders_dataset.csv | Order lifecycle and timestamps |
| `order_items` | olist_order_items_dataset.csv | Individual product lines within an order |
| `payments` | olist_order_payments_dataset.csv | Payment records per order |
| `order_reviews` | olist_order_reviews_dataset.csv | Customer satisfaction reviews |
| `products` | olist_products_dataset.csv | Product catalog with dimensions |
| `sellers` | olist_sellers_dataset.csv | Marketplace sellers |
| `geolocation` | olist_geolocation_dataset.csv | Zip-code-level lat/lon coordinates |
| `product_category_name_translation` | product_category_name_translation.csv | Portuguese to English category mapping |

---

## 2. Entity-Relationship Overview

The relationships between entities are as follows:

- A **customer** places one or more **orders** (1:N)
- An **order** contains one or more **order items** (1:N)
- An **order** has zero or one **review** (1:0..1)
- An **order** has one or more **payment** records (1:N)
- An **order item** references exactly one **product** (N:1)
- An **order item** is fulfilled by exactly one **seller** (N:1)
- A **product** belongs to one **product category** (N:1)
- A **customer** is located at one **geolocation** zip code (N:1)
- A **seller** is located at one **geolocation** zip code (N:1)

---

## 3. Resolving Many-to-Many Relationships via Bridge Tables

### The Orders ↔ Products Many-to-Many Problem

The most critical design decision in this schema is handling the relationship between `orders` and `products`. This is a classic many-to-many relationship:

- One order can contain **many products**
- One product can appear in **many orders**

Storing this directly — for example, by adding a `product_id` column to the `orders` table — would either limit each order to one product or require repeating order data for every product line. Both approaches cause data anomalies.

**Solution: The `order_items` bridge table**

We resolved this by introducing `order_items` as a bridge (associative) table. It has a **composite primary key** of `(order_id, order_item_id)` and carries the attributes that belong specifically to the relationship between an order and a product line:

- `product_id` (FK → products)
- `seller_id` (FK → sellers)
- `shipping_limit_date`
- `price`
- `freight_value`

This ensures each fact — the price of a specific product in a specific order — is stored exactly once, with no repetition or ambiguity.

### The Payments Composite Key

Similarly, `payments` uses a composite primary key of `(order_id, payment_sequential)` because a single order can be split across multiple payment methods (e.g., credit card + voucher). Each payment method gets its own sequential row.

---

## 4. First Normal Form (1NF)

Our schema satisfies 1NF because:

- Every column contains **atomic values** — no comma-separated lists, no repeating groups, no arrays
- Every row is uniquely identifiable by its primary key
- All column names are unique within each table

**Example:** Rather than storing all products in a single comma-separated `products` field on the `orders` table, each product line is its own row in `order_items` with a unique `(order_id, order_item_id)` composite key.

---

## 5. Second Normal Form (2NF)

Our schema satisfies 2NF because every non-key attribute depends on the **entire** primary key, not just part of it.

**Example — `order_items`:**

The composite PK is `(order_id, order_item_id)`. Every non-key attribute — `product_id`, `seller_id`, `price`, `freight_value`, `shipping_limit_date` — requires both parts of the key to be identified. There are no partial dependencies.

**Counter-example we avoided:** If we had stored `product_category_name_english` directly in `order_items`, it would only depend on `product_id` (not on the full composite key), creating a partial dependency. We avoided this by keeping product attributes in `products` and translations in a separate lookup table.

---

## 6. Third Normal Form (3NF)

Our schema satisfies 3NF because there are no **transitive dependencies** — no non-key attribute depends on another non-key attribute.

### Key 3NF Decisions

**Decision 1 — `product_category_name_translation` as a separate table**

In the raw dataset, products have a Portuguese `product_category_name`. The English translation of that name depends on the category name itself — not on the product. If we had stored `product_category_name_english` directly in the `products` table, we would have:

```
product_id → product_category_name → product_category_name_english
```

This is a transitive dependency: `product_category_name_english` depends on `product_category_name`, which depends on `product_id`. This violates 3NF.

**Fix:** We moved the translation into its own `product_category_name_translation` table where `product_category_name` is the primary key and `product_category_name_english` directly depends on it.

**Decision 2 — `geolocation` as a separate table**

City and state information depends on the zip code prefix — not on the customer or seller. If we stored `city` and `state` directly in `customers`, we would have:

```
customer_id → customer_zip_code_prefix → customer_city, customer_state
```

This is a transitive dependency. Two customers in the same zip code would store the same city and state, causing update anomalies (if a city name changes, every customer row in that zip must be updated).

**Fix:** We separated geographic data into a `geolocation` table keyed on `geolocation_zip_code_prefix`. Both `customers` and `sellers` reference this table via a foreign key.

**Decision 3 — `customer_id` vs `customer_unique_id`**

A quirk of the Olist dataset is that `customer_id` is created per order, not per person. A returning shopper has multiple `customer_id` values but one stable `customer_unique_id`. We preserve both:

- `customer_id` — the order-level identifier (PK in our `customers` table)
- `customer_unique_id` — the person-level identifier (used for loyalty analysis)

Merging these would conflate order-level and person-level analysis, causing incorrect aggregations.

---

## 7. How the Schema Avoids Data Anomalies

| Anomaly Type | How We Avoid It |
|-------------|-----------------|
| **Insert anomaly** | You can add a new product category without needing an order — `product_category_name_translation` is independent |
| **Update anomaly** | Changing a city name only requires updating one row in `geolocation`, not every customer/seller row |
| **Delete anomaly** | Deleting an order does not lose product or seller information — those live in their own tables |
| **Duplication** | `price` and `freight_value` are stored once per order-item line, not repeated across order and product tables |

---

## 8. Constraint Design

To enforce data integrity at the database level, we applied the following constraints:

| Constraint | Where Applied | Purpose |
|-----------|--------------|---------|
| `PRIMARY KEY` | All tables | Uniquely identifies each row |
| `FOREIGN KEY` | All FK columns | Enforces referential integrity |
| `NOT NULL` | All PK and critical FK columns | Prevents incomplete records |
| `UNIQUE` | `order_reviews.order_id` | Enforces one review per order |
| `CHECK (review_score BETWEEN 1 AND 5)` | `order_reviews` | Domain constraint on ratings |
| `CHECK (order_status IN (...))` | `orders` | Restricts to 8 known statuses |
| `CHECK (payment_type IN (...))` | `payments` | Restricts to known payment methods |
| `CHECK (price >= 0)` | `order_items` | Prices cannot be negative |
| `TIMESTAMPTZ` | All timestamp columns | Timezone-aware timestamps |
| `NUMERIC(10,2)` | All currency columns | Exact decimal arithmetic for money |

---

## 9. Summary

The OlistIQ schema is designed to be in Third Normal Form throughout. Every design decision — the `order_items` bridge table, the `geolocation` reference table, the `product_category_name_translation` lookup, and the separation of `customer_id` from `customer_unique_id` — was made to eliminate redundancy, prevent anomalies, and ensure that every fact in the database is stored in exactly one place.
