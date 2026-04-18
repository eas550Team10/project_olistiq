
WITH monthly_agg AS (
    SELECT
        DATE_TRUNC('month',o.order_purchase_timestamp) AS order_month,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(oi.price+oi.freight_value)::NUMERIC,2) AS monthly_revenue,
        COUNT(DISTINCT oi.seller_id) AS active_sellers
    FROM orders o
    JOIN order_items oi ON o.order_id=oi.order_id
    WHERE o.order_status='delivered'
    AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY DATE_TRUNC('month',o.order_purchase_timestamp)
),

revenue_trends AS (
    SELECT
        order_month,
        total_orders,
        monthly_revenue,
        active_sellers,
        -- running total across all months
        SUM(monthly_revenue) OVER (
            ORDER BY order_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue,
        -- previous month for comparison
        LAG(monthly_revenue) OVER (ORDER BY order_month) AS prev_month_revenue,
        -- month over month growth percentage
        ROUND(
            100.0*(monthly_revenue-LAG(monthly_revenue) OVER (ORDER BY order_month))
            /NULLIF(LAG(monthly_revenue) OVER (ORDER BY order_month),0)
        ,2) AS mom_growth_pct
    FROM monthly_agg
)

SELECT
    TO_CHAR(order_month,'YYYY-MM') AS month,
    total_orders,
    monthly_revenue,
    active_sellers,
    cumulative_revenue,
    prev_month_revenue,
    mom_growth_pct,
    CASE
        WHEN mom_growth_pct>0 THEN 'growth'
        WHEN mom_growth_pct<0 THEN 'decline'
        WHEN mom_growth_pct=0 THEN 'flat'
        ELSE 'first month'
    END AS trend
FROM revenue_trends
ORDER BY order_month