with orders as (
    select purchased_at from {{ ref('stg_orders') }}
    where purchased_at is not null
),

dates as (
    select distinct
        date_trunc('day', purchased_at)::date   as date_day,
        extract(year  from purchased_at)::int   as year,
        extract(month from purchased_at)::int   as month,
        extract(day   from purchased_at)::int   as day,
        extract(dow   from purchased_at)::int   as day_of_week,
        to_char(purchased_at, 'Month')          as month_name,
        to_char(purchased_at, 'Day')            as day_name,
        case
            when extract(dow from purchased_at) in (0, 6) then true
            else false
        end                                     as is_weekend
    from orders
)

select * from dates
order by date_day