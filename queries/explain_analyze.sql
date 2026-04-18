-- Explain Analyze
-- Profiled before and after indexing

-- Recorded results:
--BEFORE: 780.787 ms — Seq Scan (no indexes)
--AFTER:  315.106 ms — Index Scan (with indexes)
--Improvement: 59.6% faster


--run drop_indexes.sql first to get baseline, then run indexes.sql to recreate


EXPLAIN ANALYZE
WITH shipping_footprint AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT c.customer_state) AS states_reached,
        COUNT(DISTINCT oi.order_id) AS total_orders,
        ROUND(SUM(oi.price+oi.freight_value)::NUMERIC,2) AS total_revenue,
        ROUND(AVG(oi.price+oi.freight_value)::NUMERIC,2) AS avg_order_value
    FROM order_items oi
    JOIN orders o ON oi.order_id=o.order_id
    JOIN customers c ON o.customer_id=c.customer_id
    WHERE o.order_status='delivered'
    GROUP BY oi.seller_id
    HAVING COUNT(DISTINCT oi.order_id) >= 3
),
ranked_sellers AS (
    SELECT
        seller_id,
        states_reached,
        total_orders,
        total_revenue,
        avg_order_value,
        CASE
            WHEN states_reached=1 THEN 'local'
            WHEN states_reached BETWEEN 2 AND 8 THEN 'regional'
            WHEN states_reached>8 THEN 'national'
        END AS seller_tier,
        RANK() OVER (ORDER BY states_reached DESC) AS geo_rank,
        RANK() OVER (ORDER BY total_revenue DESC) AS rev_rank
    FROM shipping_footprint
)

SELECT
    rs.seller_id,
    s.seller_city,
    s.seller_state,
    rs.states_reached,
    rs.total_orders,
    rs.total_revenue,
    rs.avg_order_value,
    rs.seller_tier,
    rs.geo_rank,
    rs.rev_rank,
    rs.rev_rank-rs.geo_rank AS efficiency_gap
FROM ranked_sellers rs
JOIN sellers s ON rs.seller_id=s.seller_id
ORDER BY rs.geo_rank
LIMIT 50;

