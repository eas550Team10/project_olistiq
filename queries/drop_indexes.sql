
-- run this file to remove indexes and get baseline EXPLAIN ANALYZE times

DROP INDEX IF EXISTS idx_oi_seller_order;
DROP INDEX IF EXISTS idx_ord_status_customer;