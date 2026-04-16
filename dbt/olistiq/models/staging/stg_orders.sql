with source as (
    select * from {{ source('olistiq', 'orders') }}
),

renamed as (
    select
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp                                    as purchased_at,
        order_approved_at                                           as approved_at,
        order_delivered_carrier_date                                as shipped_at,
        order_delivered_customer_date                               as delivered_at,
        order_estimated_delivery_date                               as estimated_delivery_at,

        -- delivery delay in days (positive = late, negative = early)
        extract(epoch from (
            order_delivered_customer_date - order_estimated_delivery_date
        )) / 86400                                                  as delivery_delay_days,

        -- was the order delivered on time?
        case
            when order_delivered_customer_date <= order_estimated_delivery_date then true
            else false
        end                                                         as is_on_time

    from source
    where order_id is not null
)

select * from renamed