with source as (
    select * from {{ source('olistiq', 'order_items') }}
),

renamed as (
    select
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value,
        price + freight_value as total_amount
    from source
    where order_id is not null
)

select * from renamed
