# OlistIQ

OlistIQ is a data engineering pipeline built on top of the Brazilian E-Commerce dataset by Olist. We picked this dataset because it's real — messy timestamps, Portuguese category names, incomplete deliveries — the kind of thing you actually deal with outside of a classroom. The goal was to build something end to end: raw data in, clean analytical database out, with a dashboard on top that answers actual business questions.

**Course:** EAS 550 — Data Models & Query Languages · Spring 2026 · University at Buffalo

---

## The Dataset

The data comes from [Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), a Brazilian e-commerce marketplace. It covers about 100,000 orders placed between 2016 and 2018, spread across 9 CSV files — orders, customers, sellers, products, payments, reviews, and geolocation data.

---

## Phase 1 — Database Design & Ingestion

The first phase was about getting the foundation right. Before writing any transformation logic or building a dashboard, we needed a clean, well-structured database that would hold up under real queries.

### What we did

**Designed the schema from scratch.**
We analyzed all 9 CSV files to identify the core entities and how they relate to each other. The schema is normalized to Third Normal Form — no redundant data, no update anomalies, no transitive dependencies. Every design decision has a reason behind it.

**Built the ERD.**
We mapped out all entities, attributes, and relationships using Crow's Foot notation. The diagram is in `docs/erd.png`.

![ERD](docs/erd.png)

**Wrote `schema.sql`.**
Nine tables, created in the correct foreign key dependency order. We used proper data types throughout — `NUMERIC(10,2)` for all money fields, `TIMESTAMPTZ` for every timestamp, `CHAR(5)` for zip codes. All domain rules are enforced at the database level using `CHECK` constraints — review scores are locked to 1–5, order statuses can only be one of 8 known values, prices can't go negative.

**Handled the tricky parts.**

The relationship between orders and products is many-to-many — one order has multiple products, one product appears in many orders. We resolved this with `order_items` as a bridge table with a composite primary key on `(order_id, order_item_id)`. It stores price, freight cost, seller, and shipping deadline per line item.

We also pulled geolocation into its own table. City and state depend on the zip code, not on the customer or seller — storing them directly in `customers` would have created thousands of duplicate entries and a 3NF violation.

The `product_category_name_translation` table handles the Portuguese-to-English mapping separately, for the same reason. Category descriptions depend on the category name, not on individual products.

**Wrote `ingest_data.py`.**
A Python script using Pandas and SQLAlchemy that reads the CSVs, cleans them up, and loads them into Neon in the right order. It handles missing values, fixes zip code formatting, translates category names, and filters out rows that would break foreign key constraints. The script is fully idempotent — you can run it multiple times and it won't duplicate anything.

**Set up RBAC with `security.sql`.**
Two roles: `olist_analyst` for read-only access (BI tools, dbt) and `olist_app_user` for the dashboard backend (read + write on operational tables). No credentials hardcoded anywhere.

**Provisioned Neon.**
Cloud-hosted PostgreSQL on Neon's free serverless tier. We use `NullPool` in SQLAlchemy so connections close immediately after each query — Neon pauses compute after 5 minutes of inactivity, and a normal connection pool would keep it awake and burn through the free tier.

### What was created

| File | What it does |
|------|-------------|
| `schema.sql` | Creates all 9 tables with constraints and indexes |
| `ingest_data.py` | Cleans and loads all CSVs into Neon |
| `security.sql` | Creates analyst and app user roles |
| `docs/erd.png` | Entity relationship diagram |
| `docs/3nf_justification.md` | Full write-up of design decisions |
| `requirements.txt` | Python dependencies |

### Tables in Neon

```
customers
geolocation
order_items
order_reviews
orders
payments
product_category_name_translation
products
sellers
```

---

## What's Next

- **Phase 2** — dbt transformation models (Bronze → Silver → Gold star schema)
- **Phase 3** — GitHub Actions CI/CD pipeline with dbt tests on every PR
- **Phase 4** — Streamlit dashboard deployed on Render

---

## Running It

```bash
git clone https://github.com/eas550Team10/project_olistiq.git
cd project_olistiq

python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Add your Neon connection string to a `.env` file:
```
DATABASE_URL=postgresql://...
```

Run the schema and load the data:
```bash
# paste schema.sql into Neon SQL Editor, then:
python ingest_data.py --data-dir ./data
```

---