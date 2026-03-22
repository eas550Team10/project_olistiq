"""
ingest_data.py
==============
EAS 550–OlistIQ Data Ingestion Pipeline
Team 10
"""
import argparse
import os
import sys
import logging
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    log.error("DATABASE_URL not set. Add it to your .env file.")
    sys.exit(1)


def get_engine():
    return create_engine(DATABASE_URL, poolclass=NullPool)


def upsert(df, table, conflict_cols, engine):
    if df.empty:
        log.warning(f"[{table}] DataFrame is empty — skipping.")
        return 0

    df = df.where(pd.notnull(df), None)

    conflict = ", ".join(conflict_cols)

    with engine.connect() as conn:
        existing = pd.read_sql(f"SELECT {conflict} FROM {table}", conn)

    if not existing.empty:
        df = df.merge(existing, on=conflict_cols, how="left", indicator=True)
        df = df[df["_merge"] == "left_only"].drop(columns=["_merge"])

    if df.empty:
        log.info(f"[{table}] 0 new rows — already up to date")
        return 0
    df.to_sql(name=table,con=engine,if_exists="append",index=False,method="multi")

    log.info(f"[{table}] {len(df):,} rows inserted")
    return len(df)


def to_utc(col):
    return pd.to_datetime(col, errors="coerce", utc=True)


def clean_geolocation(df):
    df = df.copy()
    df["geolocation_zip_code_prefix"] = df["geolocation_zip_code_prefix"].astype(str).str.zfill(5)
    df = df.dropna(subset=["geolocation_lat", "geolocation_lng"])
    df = df.drop_duplicates(subset=["geolocation_zip_code_prefix"], keep="first")
    return df[[
        "geolocation_zip_code_prefix",
        "geolocation_lat",
        "geolocation_lng",
        "geolocation_city",
        "geolocation_state"
    ]]


def fix_categories(df):
    df = df.copy()
    df = df.dropna(subset=["product_category_name", "product_category_name_english"])
    df = df.drop_duplicates(subset=["product_category_name"], keep="first")
    return df[[
        "product_category_name",
        "product_category_name_english"
    ]]


def clean_customers(df, valid_zips):
    df = df.copy()
    df = df.dropna(subset=["customer_id", "customer_unique_id"])
    df = df.drop_duplicates(subset=["customer_id"], keep="first")
    df["customer_zip_code_prefix"] = df["customer_zip_code_prefix"].astype(str).str.zfill(5)
    df["customer_zip_code_prefix"] = df["customer_zip_code_prefix"].apply(
        lambda z: z if z in valid_zips else None
    )
    return df[[
        "customer_id",
        "customer_unique_id",
        "customer_zip_code_prefix",
        "customer_city",
        "customer_state"
    ]]


def clean_sellers(df, valid_zips):
    df = df.copy()
    df = df.dropna(subset=["seller_id"])
    df = df.drop_duplicates(subset=["seller_id"], keep="first")
    df["seller_zip_code_prefix"]=df["seller_zip_code_prefix"].astype(str).str.strip().str.zfill(5)
    df["seller_zip_code_prefix"]=df["seller_zip_code_prefix"].apply(
    lambda z: z if z in valid_zips else None
)
    return df[[
        "seller_id",
        "seller_zip_code_prefix",
        "seller_city",
        "seller_state"
    ]]


def clean_products(df, valid_categories):
    df = df.copy()
    df["product_id"] = df["product_id"].astype("string").str.strip()
    df["product_category_name"] = df["product_category_name"].astype("string").str.strip()
    numeric_cols = [
        "product_name_lenght",
        "product_description_lenght",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df = df.dropna(subset=["product_id"])
    df["product_category_name"]=df["product_category_name"].astype(str).str.strip()
    df.loc[~df["product_category_name"].isin(valid_categories), "product_category_name"]=pd.NA
    df = df.drop_duplicates(subset=["product_id"], keep="first")
    return df[[
        "product_id",
        "product_category_name",
        "product_name_lenght",
        "product_description_lenght",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm"
    ]]


def clean_orders(df, valid_customers):
    df = df.copy()
    df = df.dropna(subset=["order_id", "customer_id", "order_status"])
    df = df.drop_duplicates(subset=["order_id"], keep="first")
    df = df[df["customer_id"].isin(valid_customers)]
    valid_statuses = {
        "created", "approved", "invoiced", "processing",
        "shipped", "delivered", "unavailable", "canceled"
    }
    df = df[df["order_status"].isin(valid_statuses)]
    ts_cols = [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date"
    ]
    for col in ts_cols:
        df[col] = to_utc(df[col])
    return df[["order_id", "customer_id", "order_status"] + ts_cols]


def clean_order_items(df, valid_orders, valid_products, valid_sellers):
    df = df.copy()
    df = df.dropna(subset=["order_id", "order_item_id", "product_id", "seller_id"])
    df = df.drop_duplicates(subset=["order_id", "order_item_id"], keep="first")
    df = df[
        df["order_id"].isin(valid_orders) &
        df["product_id"].isin(valid_products) &
        df["seller_id"].isin(valid_sellers)
    ]
    df["price"] = pd.to_numeric(df["price"], errors="coerce")
    df["freight_value"] = pd.to_numeric(df["freight_value"], errors="coerce")
    df = df.dropna(subset=["price", "freight_value"])
    df = df[(df["price"] >= 0) & (df["freight_value"] >= 0)]
    df["order_item_id"] = df["order_item_id"].astype(int)
    df["shipping_limit_date"] = to_utc(df["shipping_limit_date"])
    return df[[
        "order_id",
        "order_item_id",
        "product_id",
        "seller_id",
        "shipping_limit_date",
        "price",
        "freight_value"
    ]]


def clean_payments(df, valid_orders):
    df = df.copy()
    df["payment_sequential"] = pd.to_numeric(df["payment_sequential"], errors="coerce").astype("Int64")
    df["payment_installments"] = pd.to_numeric(df["payment_installments"], errors="coerce").astype("Int64")
    df["payment_value"] = pd.to_numeric(df["payment_value"], errors="coerce")
    df = df.dropna(subset=["order_id", "payment_sequential", "payment_type", "payment_installments", "payment_value"])
    allowed_types = {"credit_card", "boleto", "voucher", "debit_card", "not_defined"}
    df = df[df["order_id"].isin(valid_orders)]
    df = df[df["payment_type"].isin(allowed_types)]
    df = df[(df["payment_installments"] >= 1) & (df["payment_value"] >= 0)]
    df = df.drop_duplicates(subset=["order_id", "payment_sequential"], keep="first")
    return df[[
        "order_id",
        "payment_sequential",
        "payment_type",
        "payment_installments",
        "payment_value"
    ]]


def clean_reviews(df, valid_orders):
    df = df.copy()
    df["review_score"] = pd.to_numeric(df["review_score"], errors="coerce").astype("Int64")
    df = df.dropna(subset=["review_id", "order_id", "review_score"])
    df = df[df["order_id"].isin(valid_orders)]
    df = df[df["review_score"].between(1, 5)]
    df = df.drop_duplicates(subset=["order_id"], keep="first")
    return df


def run(data_dir):
    engine = get_engine()
    data_dir = Path(data_dir)

    df_geo = pd.read_csv(data_dir / "olist_geolocation_dataset.csv")
    df_cat = pd.read_csv(data_dir / "product_category_name_translation.csv")
    df_cust = pd.read_csv(data_dir / "olist_customers_dataset.csv")
    df_sell = pd.read_csv(data_dir / "olist_sellers_dataset.csv")
    df_prod = pd.read_csv(data_dir / "olist_products_dataset.csv")
    df_ord = pd.read_csv(data_dir / "olist_orders_dataset.csv")
    df_items = pd.read_csv(data_dir / "olist_order_items_dataset.csv")
    df_pay = pd.read_csv(data_dir / "olist_order_payments_dataset.csv")
    df_rev = pd.read_csv(data_dir / "olist_order_reviews_dataset.csv")

    df_geo = clean_geolocation(df_geo)
    df_cat = fix_categories(df_cat)

    valid_zips = set(df_geo["geolocation_zip_code_prefix"].dropna().astype(str))
    valid_categories = set(df_cat["product_category_name"].dropna().astype(str))

    df_cust = clean_customers(df_cust, valid_zips)
    df_sell = clean_sellers(df_sell, valid_zips)
    df_prod = clean_products(df_prod, valid_categories)

    df_ord = clean_orders(df_ord, set(df_cust["customer_id"].dropna().astype(str)))

    valid_orders = set(df_ord["order_id"].dropna().astype(str))
    valid_products = set(df_prod["product_id"].dropna().astype(str))
    valid_sellers = set(df_sell["seller_id"].dropna().astype(str))

    df_items = clean_order_items(df_items, valid_orders, valid_products, valid_sellers)
    df_pay = clean_payments(df_pay, valid_orders)
    df_rev = clean_reviews(df_rev, valid_orders)

    upsert(df_geo, "geolocation", ["geolocation_zip_code_prefix"], engine)
    upsert(df_cat, "product_category_name_translation", ["product_category_name"], engine)
    upsert(df_cust, "customers", ["customer_id"], engine)

    upsert(df_sell, "sellers", ["seller_id"], engine)
    upsert(df_prod, "products", ["product_id"], engine)

    upsert(df_ord, "orders", ["order_id"], engine)

    upsert(df_items, "order_items", ["order_id", "order_item_id"], engine)
    upsert(df_pay, "payments", ["order_id", "payment_sequential"], engine)
    upsert(df_rev, "order_reviews", ["review_id"], engine)

    engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="olistiq ingestion pipeline")
    parser.add_argument("--data-dir", default="./data")
    args = parser.parse_args()
    run(args.data_dir)