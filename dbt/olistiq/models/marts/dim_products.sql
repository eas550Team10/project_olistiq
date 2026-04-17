with products as (
    select * from {{ ref('stg_products') }}
)

select
    product_id,
    product_category_name,
    category_name_english,
    product_photos_qty,
    weight_g,
    length_cm,
    height_cm,
    width_cm
from products
