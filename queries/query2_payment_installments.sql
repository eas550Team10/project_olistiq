
WITH state_stats AS (
    SELECT
        c.customer_state,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(AVG(p.payment_installments)::NUMERIC,2) AS avg_installments,
        ROUND(AVG(p.payment_value)::NUMERIC,2) AS avg_payment_value,
        ROUND(SUM(p.payment_value)::NUMERIC,2) AS total_revenue,
        ROUND(
            100.0*COUNT(CASE WHEN p.payment_installments>1 THEN 1 END)
            /COUNT(*),2
        ) AS pct_installment_orders
    FROM payments p
    JOIN orders o ON p.order_id=o.order_id
    JOIN customers c ON o.customer_id=c.customer_id
    WHERE o.order_status='delivered'
    AND p.payment_type='credit_card'
    GROUP BY c.customer_state
    HAVING COUNT(DISTINCT o.order_id) >= 100
),

state_ranked AS (
    SELECT
        customer_state,
        total_orders,
        avg_installments,
        avg_payment_value,
        total_revenue,
        pct_installment_orders,
        -- bucket states into 4 groups by installment preference
        NTILE(4) OVER (ORDER BY avg_installments DESC) AS installment_bucket,
        RANK() OVER (ORDER BY avg_installments DESC) AS installment_rank,
        RANK() OVER (ORDER BY avg_payment_value DESC) AS spending_rank,
        -- how far each state deviates from the national average
        ROUND(avg_installments-AVG(avg_installments) OVER (),2) AS diff_from_avg
    FROM state_stats
)

SELECT
    customer_state,
    total_orders,
    avg_installments,
    avg_payment_value,
    total_revenue,
    pct_installment_orders,
    CASE installment_bucket
        WHEN 1 THEN 'high installment state'
        WHEN 2 THEN 'above average'
        WHEN 3 THEN 'below average'
        WHEN 4 THEN 'low installment state'
    END AS installment_profile,
    installment_rank,
    spending_rank,
    diff_from_avg
FROM state_ranked
ORDER BY installment_rank