with source as (
    select * from {{ source('olistiq', 'order_reviews') }}
),

renamed as (
    select
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp,
        case
            when review_score >= 4 then 'positive'
            when review_score = 3  then 'neutral'
            else 'negative'
        end                         as sentiment
    from source
    where review_id is not null
)

select * from renamed