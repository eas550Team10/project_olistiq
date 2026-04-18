
-- run this file to remove ADD indexes and get EXPLAIN ANALYZE times


CREATE INDEX IF NOT EXISTS idx_oi_seller_order
ON order_items(seller_id,order_id);
CREATE INDEX IF NOT EXISTS idx_ord_status_customer
ON orders(order_status,order_id,customer_id);