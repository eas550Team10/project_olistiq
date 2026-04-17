with orders as (
    select * from {{ ref('stg_orders') }}
),

order_items as (
    select
        order_id,
        count(*) as item_count,
        sum(price) as total_price,
        sum(freight_value) as total_freight,
        sum(total_amount) as total_order_value
    from {{ ref('stg_order_items') }}
    group by order_id
),

payments as (
    select
        order_id,
        sum(payment_value) as total_payment,
        count(*) as payment_count,
        max(payment_type) as primary_payment_type
    from {{ ref('stg_payments') }}
    group by order_id
),

reviews as (
    select
        order_id,
        review_score,
        sentiment
    from {{ ref('stg_order_reviews') }}
)

select
    o.order_id,
    o.customer_id,
    o.order_status,
    o.purchased_at,
    o.approved_at,
    o.shipped_at,
    o.delivered_at,
    o.estimated_delivery_at,
    o.delivery_delay_days,
    o.is_on_time,
    i.item_count,
    i.total_price,
    i.total_freight,
    i.total_order_value,
    p.total_payment,
    p.payment_count,
    p.primary_payment_type,
    r.review_score,
    r.sentiment
from orders as o
left join order_items as i on o.order_id = i.order_id
left join payments as p on o.order_id = p.order_id
left join reviews as r on o.order_id = r.order_id
