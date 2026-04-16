with customers as (
    select * from {{ ref('stg_customers') }}
)

select
    customer_id,
    customer_unique_id,
    zip_code,
    city,
    state
from customers