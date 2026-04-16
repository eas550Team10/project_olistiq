with source as (
    select * from {{ source('olistiq', 'products') }}
),

renamed as (
    select
        p.product_id,
        p.product_category_name,
        t.product_category_name_english     as category_name_english,
        p.product_name_lenght               as product_name_length,
        p.product_description_lenght        as product_description_length,
        p.product_photos_qty,
        p.product_weight_g                  as weight_g,
        p.product_length_cm                 as length_cm,
        p.product_height_cm                 as height_cm,
        p.product_width_cm                  as width_cm
    from source p
    left join {{ source('olistiq', 'product_category_name_translation') }} t
        on p.product_category_name = t.product_category_name
    where p.product_id is not null
)

select * from renamed