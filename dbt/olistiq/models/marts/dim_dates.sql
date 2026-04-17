with orders as (
    select purchased_at from {{ ref('stg_orders') }}
    where purchased_at is not null
),

dates as (
    select distinct
        date_trunc('day', purchased_at)::date as date_day,
        extract(year from purchased_at)::int as year_num,
        extract(month from purchased_at)::int as month_num,
        extract(day from purchased_at)::int as day_num,
        extract(dow from purchased_at)::int as day_of_week,
        to_char(purchased_at, 'Month') as month_name,
        to_char(purchased_at, 'Day') as day_name,
        coalesce(extract(dow from purchased_at) in (0, 6), false) as is_weekend
    from orders
)

select * from dates
order by date_day
