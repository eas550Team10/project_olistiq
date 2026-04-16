# OlistIQ — dbt Project

This dbt project transforms the raw Olist Bronze layer into a clean
analytical Star Schema (Gold layer) using the Medallion Architecture.

## Structure
models/
├── staging/          # Bronze → Silver (views)
│   ├── sources.yml
│   ├── schema.yml
│   ├── stg_orders.sql
│   ├── stg_customers.sql
│   ├── stg_sellers.sql
│   ├── stg_products.sql
│   ├── stg_order_items.sql
│   ├── stg_payments.sql
│   └── stg_order_reviews.sql
└── marts/            # Silver → Gold (tables)
├── schema.yml
├── fct_orders.sql
├── dim_customers.sql
├── dim_sellers.sql
├── dim_products.sql
└── dim_dates.sql

## Running

```bash
dbt run          # build all models
dbt test         # run all 31 data quality tests
dbt docs generate && dbt docs serve   # view lineage graph
```

## Tests

31 data quality tests covering:
- Unique and not_null on all primary keys
- Referential integrity between fct_orders and dimensions
- Accepted values for review_score (1-5) and order_status
