-- =============================================================
-- OlistIQ: schema.sql
-- EAS 550 – Data Models & Query Languages (Spring 2026)
-- Team 10
--
-- Load order respects FK dependencies:
--   geolocation → product_category_name_translation
--   → customers → sellers → products → orders
--   → order_items → payments → order_reviews
-- =============================================================

-- Drop tables in reverse FK order for clean re-runs
DROP TABLE IF EXISTS order_reviews       CASCADE;
DROP TABLE IF EXISTS payments            CASCADE;
DROP TABLE IF EXISTS order_items         CASCADE;
DROP TABLE IF EXISTS orders              CASCADE;
DROP TABLE IF EXISTS products            CASCADE;
DROP TABLE IF EXISTS sellers             CASCADE;
DROP TABLE IF EXISTS customers           CASCADE;
DROP TABLE IF EXISTS product_category_name_translation CASCADE;
DROP TABLE IF EXISTS geolocation         CASCADE;


-- ---------------------------------------------------------------
-- 1. geolocation
--    Zip-level lat/lon reference table.
--    Both customers and sellers reference zip codes from here.
--    PK is the zip prefix — multiple rows per zip in the raw CSV
--    are deduplicated during ingestion (first-row-wins).
-- ---------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix  CHAR(5)        NOT NULL,
    geolocation_lat              NUMERIC(9, 6)  NOT NULL,
    geolocation_lng              NUMERIC(9, 6)  NOT NULL,
    geolocation_city             TEXT           NOT NULL,
    geolocation_state            CHAR(2)        NOT NULL,
    CONSTRAINT pk_geolocation PRIMARY KEY (geolocation_zip_code_prefix)
);

COMMENT ON TABLE  geolocation IS 'Zip-code-level lat/lon for Brazil. One representative row per zip prefix after dedup.';
COMMENT ON COLUMN geolocation.geolocation_zip_code_prefix IS 'Brazilian CEP prefix (5 digits). Natural PK after dedup.';


-- ---------------------------------------------------------------
-- 2. product_category_name_translation
--    Maps Portuguese category names → English.
--    Referenced by products.product_category_name.
-- ---------------------------------------------------------------
CREATE TABLE product_category_name_translation (
    product_category_name         TEXT NOT NULL,
    product_category_name_english TEXT NOT NULL,
    CONSTRAINT pk_category_translation PRIMARY KEY (product_category_name)
);

COMMENT ON TABLE product_category_name_translation IS 'Portuguese-to-English lookup for product categories.';


-- ---------------------------------------------------------------
-- 3. customers
--    One row per customer_id (order-level customer record).
--    customer_unique_id de-duplicates returning shoppers across orders.
-- ---------------------------------------------------------------
CREATE TABLE customers (
    customer_id              TEXT    NOT NULL,
    customer_unique_id       TEXT    NOT NULL,
    customer_zip_code_prefix CHAR(5),                          -- nullable: some zips not in geolocation
    customer_city            TEXT,
    customer_state           CHAR(2),
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT fk_customers_geo FOREIGN KEY (customer_zip_code_prefix)
        REFERENCES geolocation (geolocation_zip_code_prefix)
        ON DELETE SET NULL
);

COMMENT ON TABLE  customers IS 'One record per order-customer pair. customer_unique_id links a person across orders.';
COMMENT ON COLUMN customers.customer_unique_id IS 'Stable identifier for a returning shopper across multiple orders.';


-- ---------------------------------------------------------------
-- 4. sellers
--    Marketplace sellers. Each seller has one zip code.
-- ---------------------------------------------------------------
CREATE TABLE sellers (
    seller_id              TEXT    NOT NULL,
    seller_zip_code_prefix CHAR(5),
    seller_city            TEXT,
    seller_state           CHAR(2),
    CONSTRAINT pk_sellers PRIMARY KEY (seller_id),
    CONSTRAINT fk_sellers_geo FOREIGN KEY (seller_zip_code_prefix)
        REFERENCES geolocation (geolocation_zip_code_prefix)
        ON DELETE SET NULL
);

COMMENT ON TABLE sellers IS 'Marketplace seller registry. Zip links to geolocation for regional analysis.';


-- ---------------------------------------------------------------
-- 5. products
--    Product catalog. Category name is a FK to translation table.
--    Physical dimensions stored for logistics analysis.
-- ---------------------------------------------------------------
CREATE TABLE products (
    product_id                   TEXT           NOT NULL,
    product_category_name        TEXT,                         -- nullable: some products have no category
    product_name_lenght          SMALLINT       CHECK (product_name_lenght > 0),
    product_description_lenght   INT            CHECK (product_description_lenght >= 0),
    product_photos_qty           SMALLINT       CHECK (product_photos_qty >= 0),
    product_weight_g             NUMERIC(10, 2) CHECK (product_weight_g > 0),
    product_length_cm            NUMERIC(6, 2)  CHECK (product_length_cm > 0),
    product_height_cm            NUMERIC(6, 2)  CHECK (product_height_cm > 0),
    product_width_cm             NUMERIC(6, 2)  CHECK (product_width_cm > 0),
    CONSTRAINT pk_products PRIMARY KEY (product_id),
    CONSTRAINT fk_products_category FOREIGN KEY (product_category_name)
        REFERENCES product_category_name_translation (product_category_name)
        ON DELETE SET NULL
);

COMMENT ON TABLE  products IS 'Product catalog with physical dimensions for shipping/logistics analysis.';
COMMENT ON COLUMN products.product_category_name IS 'Portuguese category name; join to product_category_name_translation for English.';


-- ---------------------------------------------------------------
-- 6. orders
--    Core fact spine. Each order belongs to one customer.
--    All timestamp columns use TIMESTAMPTZ (UTC-aware).
--    order_status uses CHECK to enforce known domain values.
-- ---------------------------------------------------------------
CREATE TABLE orders (
    order_id                        TEXT         NOT NULL,
    customer_id                     TEXT         NOT NULL,
    order_status                    TEXT         NOT NULL
        CHECK (order_status IN (
            'created','approved','invoiced','processing',
            'shipped','delivered','unavailable','canceled'
        )),
    order_purchase_timestamp        TIMESTAMPTZ,
    order_approved_at               TIMESTAMPTZ,
    order_delivered_carrier_date    TIMESTAMPTZ,
    order_delivered_customer_date   TIMESTAMPTZ,
    order_estimated_delivery_date   TIMESTAMPTZ,
    CONSTRAINT pk_orders     PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_cust FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE  orders IS 'Order lifecycle table. Delivery delay = order_delivered_customer_date - order_estimated_delivery_date.';
COMMENT ON COLUMN orders.order_status IS 'Lifecycle status. CHECK enforces the 8 known Olist statuses.';


-- ---------------------------------------------------------------
-- 7. order_items
--    Bridge table resolving the M:N between orders and products.
--    Composite PK: (order_id, order_item_id).
--    A single order can have multiple items from different sellers.
-- ---------------------------------------------------------------
CREATE TABLE order_items (
    order_id             TEXT           NOT NULL,
    order_item_id        SMALLINT       NOT NULL,   -- sequential item number within order
    product_id           TEXT           NOT NULL,
    seller_id            TEXT           NOT NULL,
    shipping_limit_date  TIMESTAMPTZ,
    price                NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    freight_value        NUMERIC(10, 2) NOT NULL CHECK (freight_value >= 0),
    CONSTRAINT pk_order_items   PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_items_order   FOREIGN KEY (order_id)
        REFERENCES orders   (order_id)   ON DELETE CASCADE,
    CONSTRAINT fk_items_product FOREIGN KEY (product_id)
        REFERENCES products (product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_items_seller  FOREIGN KEY (seller_id)
        REFERENCES sellers  (seller_id)  ON DELETE RESTRICT
);

COMMENT ON TABLE  order_items IS 'Bridge table: one row per product line within an order. Resolves orders ↔ products M:N.';
COMMENT ON COLUMN order_items.order_item_id IS 'Sequential line number within an order (1-based). Part of composite PK.';


-- ---------------------------------------------------------------
-- 8. payments
--    An order can be split across multiple payment methods
--    (e.g., credit card + voucher). Sequential within order.
--    No surrogate PK needed; (order_id, payment_sequential) is natural.
-- ---------------------------------------------------------------
CREATE TABLE payments (
    order_id             TEXT           NOT NULL,
    payment_sequential   SMALLINT       NOT NULL,
    payment_type         TEXT           NOT NULL
        CHECK (payment_type IN ('credit_card','boleto','voucher','debit_card','not_defined')),
    payment_installments SMALLINT       NOT NULL CHECK (payment_installments >= 1),
    payment_value        NUMERIC(10, 2) NOT NULL CHECK (payment_value >= 0),
    CONSTRAINT pk_payments     PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_payments_ord FOREIGN KEY (order_id)
        REFERENCES orders (order_id) ON DELETE CASCADE
);

COMMENT ON TABLE  payments IS 'Payment records per order. Multiple rows per order when split-tender is used.';
COMMENT ON COLUMN payments.payment_sequential IS 'Position in a multi-tender split. Part of composite PK.';


-- ---------------------------------------------------------------
-- 9. order_reviews
--    One review per order (enforced by UNIQUE on order_id).
--    review_score constrained to 1–5.
-- ---------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id                  TEXT       NOT NULL,
    order_id                   TEXT       NOT NULL,
    review_score               SMALLINT   NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title       TEXT,
    review_comment_message     TEXT,
    review_creation_date       TIMESTAMPTZ,
    review_answer_timestamp    TIMESTAMPTZ,
    CONSTRAINT pk_reviews      PRIMARY KEY (review_id),
    CONSTRAINT uq_review_order UNIQUE (order_id),              -- one review per order
    CONSTRAINT fk_reviews_ord  FOREIGN KEY (order_id)
        REFERENCES orders (order_id) ON DELETE CASCADE
);

COMMENT ON TABLE  order_reviews IS 'Customer satisfaction reviews. UNIQUE(order_id) enforces one review per order.';
COMMENT ON COLUMN order_reviews.review_score IS '1–5 star rating. CHECK constraint enforced at DB level.';


-- ---------------------------------------------------------------
-- Indexes for common analytical query patterns
-- ---------------------------------------------------------------

-- Delivery delay analysis (orders)
CREATE INDEX idx_orders_status           ON orders (order_status);
CREATE INDEX idx_orders_purchase_ts      ON orders (order_purchase_timestamp);
CREATE INDEX idx_orders_delivered_ts     ON orders (order_delivered_customer_date);

-- Seller performance queries
CREATE INDEX idx_items_seller            ON order_items (seller_id);
CREATE INDEX idx_items_product           ON order_items (product_id);

-- Revenue by category
CREATE INDEX idx_products_category       ON products (product_category_name);

-- Review score distribution
CREATE INDEX idx_reviews_score           ON order_reviews (review_score);

-- Geographic lookups
CREATE INDEX idx_customers_state         ON customers (customer_state);
CREATE INDEX idx_sellers_state           ON sellers (seller_state);