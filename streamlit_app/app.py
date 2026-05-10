"""
OlistIQ - Streamlit Dashboard
EAS 550 - Team 10
"""
import os
import streamlit as st
import pandas as pd
import plotly.express as px
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool
from dotenv import load_dotenv

load_dotenv()

# basic page setup
st.set_page_config(
    page_title="OlistIQ",
    page_icon="🛒",
    layout="wide",
    initial_sidebar_state="expanded"
)

# clean up the default streamlit look a bit
st.markdown("""
    <style>
        .block-container { padding-top: 2rem; }
        h1 { font-size: 1.8rem; }
        h2 { font-size: 1.3rem; color: #444; }
    </style>
""", unsafe_allow_html=True)


# Database connection
# NullPool closes connections right after each query
# This keeps Neon free-tier compute from staying awake
# DATABASE_URL comes from .env

@st.cache_resource
def get_engine():
    url = os.getenv("DATABASE_URL")
    if not url:
        st.error("DATABASE_URL not set. Add it to your .env file or environment.")
        st.stop()
    return create_engine(url, poolclass=NullPool)


# Data loading functions
# All queries hit Neon directly (no CSV files)
# @st.cache_data caches results so we don't query on every click
# TTL=300 means data refreshes every 5 minutes

@st.cache_data(ttl=300)
def load_kpis():
    # summary numbers for the top of the overview page
    query = """
        SELECT
            COUNT(order_id)                                       AS total_orders,
            ROUND(SUM(total_order_value)::numeric, 2)             AS total_revenue,
            ROUND(AVG(review_score)::numeric, 2)                  AS avg_review,
            ROUND(AVG(total_order_value)::numeric, 2)             AS avg_order_value,
            ROUND(
                COUNT(CASE WHEN is_on_time = TRUE THEN 1 END) * 100.0
                / NULLIF(COUNT(order_id), 0)
            , 1)                                                   AS on_time_pct
        FROM public_marts.fct_orders
        WHERE order_status = 'delivered'
    """
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn).iloc[0]


@st.cache_data(ttl=300)
def load_monthly_revenue():
    # month by month revenue (used for the trend chart)
    query = """
        SELECT
            DATE_TRUNC('month', purchased_at)::date         AS month,
            COUNT(order_id)                                  AS total_orders,
            ROUND(SUM(total_order_value)::numeric, 2)        AS revenue
        FROM public_marts.fct_orders
        WHERE order_status = 'delivered'
          AND purchased_at IS NOT NULL
        GROUP BY 1
        ORDER BY 1
    """
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn)


@st.cache_data(ttl=300)
def load_order_status():
    # how many orders are in each status
    query = """
        SELECT order_status, COUNT(*) AS total
        FROM public_marts.fct_orders
        GROUP BY order_status
        ORDER BY total DESC
    """
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn)


@st.cache_data(ttl=300)
def load_revenue_by_state():
    # top 10 states by revenue (joins fact table with customer dimension)
    query = """
        SELECT
            c.state,
            COUNT(DISTINCT f.order_id)                       AS total_orders,
            ROUND(SUM(f.total_order_value)::numeric, 2)      AS revenue,
            ROUND(AVG(f.review_score)::numeric, 2)           AS avg_review
        FROM public_marts.fct_orders f
        JOIN public_marts.dim_customers c ON f.customer_id = c.customer_id
        WHERE f.order_status = 'delivered'
        GROUP BY c.state
        ORDER BY revenue DESC
        LIMIT 10
    """
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn)


@st.cache_data(ttl=300)
def load_review_distribution():
    # count of reviews for each score from 1 to 5
    query = """
        SELECT
            review_score,
            COUNT(*) AS total
        FROM public_marts.fct_orders
        WHERE review_score IS NOT NULL
        GROUP BY review_score
        ORDER BY review_score
    """
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn)


@st.cache_data(ttl=300)
def load_delivery_stats(state_filter: str):
    # on-time vs late delivery stats, filtered by state if one is selected
    # state is passed as a function arg so cache works correctly per selection
    if state_filter and state_filter != "All":
        query = text("""
            SELECT
                f.is_on_time,
                ROUND(AVG(f.delivery_delay_days)::numeric, 2)  AS avg_delay,
                COUNT(*)                                         AS total_orders,
                ROUND(AVG(f.review_score)::numeric, 2)          AS avg_review
            FROM public_marts.fct_orders f
            JOIN public_marts.dim_customers c ON f.customer_id = c.customer_id
            WHERE f.order_status = 'delivered'
              AND c.state = :state
            GROUP BY f.is_on_time
        """)
        with get_engine().connect() as conn:
            return pd.read_sql(query, conn, params={"state": state_filter})
    else:
        query = text("""
            SELECT
                is_on_time,
                ROUND(AVG(delivery_delay_days)::numeric, 2)    AS avg_delay,
                COUNT(*)                                         AS total_orders,
                ROUND(AVG(review_score)::numeric, 2)            AS avg_review
            FROM public_marts.fct_orders
            WHERE order_status = 'delivered'
            GROUP BY is_on_time
        """)
        with get_engine().connect() as conn:
            return pd.read_sql(query, conn)


@st.cache_data(ttl=600)
def load_states():
    # list of states for the sidebar filter dropdown
    with get_engine().connect() as conn:
        result = pd.read_sql(
            text("SELECT DISTINCT state FROM public_marts.dim_customers WHERE state IS NOT NULL ORDER BY state"),
            conn
        )
    return ["All"] + result["state"].tolist()


@st.cache_data(ttl=300)
def load_payment_types():
    # payment method breakdown (credit card, boleto, etc.)
    query = """
        SELECT
            primary_payment_type                        AS payment_type,
            COUNT(*)                                    AS total_orders,
            ROUND(AVG(total_payment)::numeric, 2)       AS avg_payment
        FROM public_marts.fct_orders
        WHERE primary_payment_type IS NOT NULL
        GROUP BY primary_payment_type
        ORDER BY total_orders DESC
    """
    with get_engine().connect() as conn:
        return pd.read_sql(text(query), conn)


# Sidebar

st.sidebar.image("https://img.icons8.com/color/96/shopping-cart.png", width=60)
st.sidebar.title("OlistIQ")
st.sidebar.caption("Brazilian E-Commerce Analytics")
st.sidebar.divider()

page = st.sidebar.radio(
    "Navigate",
    ["Overview", "Sellers", "Delivery & Reviews"]
)

states = load_states()
selected_state = st.sidebar.selectbox("Filter by State", states)

st.sidebar.divider()
st.sidebar.caption("EAS 550 · Team 10 · Spring 2026")


# Page 1: Overview

if page == "Overview":
    st.title("OlistIQ - Business Overview")
    st.caption("Live data from Neon PostgreSQL · Olist Brazilian E-Commerce 2016–2018")
    st.divider()

    # top level KPI numbers
    kpis = load_kpis()
    col1, col2, col3, col4, col5 = st.columns(5)
    col1.metric("Total Orders", f"{int(kpis['total_orders']):,}")
    col2.metric("Total Revenue", f"R$ {float(kpis['total_revenue']):,.0f}")
    col3.metric("Avg Order Value", f"R$ {float(kpis['avg_order_value']):,.2f}")
    col4.metric("Avg Review Score", f"{float(kpis['avg_review']):.2f} / 5")
    col5.metric("On-Time Rate", f"{float(kpis['on_time_pct']):.1f}%")

    st.divider()

    # revenue trend with a date range slider so users can zoom in
    st.subheader("Monthly Revenue Trend")
    df_rev = load_monthly_revenue()

    if not df_rev.empty:
        months = df_rev["month"].tolist()
        if len(months) >= 2:
            min_i, max_i = st.select_slider(
                "Select date range",
                options=list(range(len(months))),
                value=(0, len(months) - 1),
                format_func=lambda i: str(months[i])
            )
            df_rev = df_rev.iloc[min_i:max_i + 1]

        fig = px.area(
            df_rev, x="month", y="revenue",
            labels={"month": "Month", "revenue": "Revenue (R$)"},
            color_discrete_sequence=["#2563eb"]
        )
        fig.update_layout(
            hovermode="x unified",
            height=380,
            plot_bgcolor="white",
            paper_bgcolor="white",
            xaxis=dict(showgrid=True, gridcolor="#f0f0f0"),
            yaxis=dict(showgrid=True, gridcolor="#f0f0f0")
        )
        st.plotly_chart(fig, use_container_width=True)

    st.divider()

    # two smaller charts side by side at the bottom
    left, right = st.columns(2)

    with left:
        st.subheader("Order Status Breakdown")
        df_status = load_order_status()
        if not df_status.empty:
            fig2 = px.pie(
                df_status, names="order_status", values="total",
                color_discrete_sequence=px.colors.qualitative.Pastel,
                hole=0.4
            )
            fig2.update_layout(height=400)
            st.plotly_chart(fig2, use_container_width=True)

    with right:
        st.subheader("Payment Methods")
        df_pay = load_payment_types()
        if not df_pay.empty:
            fig3 = px.bar(
                df_pay, x="payment_type", y="total_orders",
                color="payment_type",
                labels={"payment_type": "Payment Type", "total_orders": "Orders"},
                color_discrete_sequence=px.colors.qualitative.Pastel
            )
            fig3.update_layout(height=350, showlegend=False, plot_bgcolor="white")
            st.plotly_chart(fig3, use_container_width=True)


# Page 2: Sellers

elif page == "Sellers":
    st.title("Seller Performance by State")
    st.caption("Live from Neon PostgreSQL")
    st.divider()

    df_sellers = load_revenue_by_state()

    if not df_sellers.empty:
        st.subheader("Top 10 States by Revenue")
        fig = px.bar(
            df_sellers,
            x="revenue", y="state",
            orientation="h",
            color="avg_review",
            color_continuous_scale="RdYlGn",
            labels={
                "revenue": "Revenue (R$)",
                "state": "State",
                "avg_review": "Avg Review Score"
            },
            text="revenue"
        )
        fig.update_traces(texttemplate="R$ %{text:,.0f}", textposition="outside")
        fig.update_layout(
            height=480,
            yaxis={"categoryorder": "total ascending"},
            plot_bgcolor="white"
        )
        st.plotly_chart(fig, use_container_width=True)

        st.subheader("State Summary")
        st.dataframe(
            df_sellers.rename(columns={
                "state": "State",
                "total_orders": "Orders",
                "revenue": "Revenue (R$)",
                "avg_review": "Avg Review"
            }),
            use_container_width=True,
            hide_index=True
        )


# Page 3: Delivery & Reviews

elif page == "Delivery & Reviews":
    st.title("Delivery Performance & Review Analysis")
    st.caption(f"State filter: {selected_state} · Live from Neon PostgreSQL")
    st.divider()

    col1, col2 = st.columns(2)

    # review score distribution bar chart
    with col1:
        st.subheader("Review Score Distribution")
        df_reviews = load_review_distribution()
        if not df_reviews.empty:
            df_reviews["review_score"] = df_reviews["review_score"].astype(str)
            fig = px.bar(
                df_reviews,
                x="review_score", y="total",
                color="review_score",
                color_discrete_map={
                    "1": "#ef4444", "2": "#f97316",
                    "3": "#eab308", "4": "#84cc16", "5": "#22c55e"
                },
                labels={"review_score": "Score (1-5)", "total": "Number of Reviews"}
            )
            fig.update_layout(height=360, showlegend=False, plot_bgcolor="white")
            st.plotly_chart(fig, use_container_width=True)

    # on-time vs late pie chart, filtered by selected state
    with col2:
        st.subheader("On-Time vs Late Deliveries")
        df_delivery = load_delivery_stats(selected_state)
        if not df_delivery.empty:
            df_delivery["status"] = df_delivery["is_on_time"].map(
                {True: "On Time", False: "Late", 1: "On Time", 0: "Late"}
            )
            fig2 = px.pie(
                df_delivery,
                names="status", values="total_orders",
                color="status",
                color_discrete_map={"On Time": "#22c55e", "Late": "#ef4444"},
                hole=0.4
            )
            fig2.update_layout(height=360)
            st.plotly_chart(fig2, use_container_width=True)

    st.divider()

    # how delivery timing affects review scores
    st.subheader("Impact of Delivery Timing on Review Scores")
    if not df_delivery.empty and "status" in df_delivery.columns:
        fig3 = px.bar(
            df_delivery,
            x="status", y="avg_review",
            color="status",
            color_discrete_map={"On Time": "#22c55e", "Late": "#ef4444"},
            labels={"avg_review": "Avg Review Score", "status": "Delivery Status"},
            text="avg_review"
        )
        fig3.update_traces(texttemplate="%{text:.2f}", textposition="outside")
        fig3.update_layout(
            height=380,
            showlegend=False,
            yaxis_range=[0, 5.5],
            plot_bgcolor="white"
        )
        st.plotly_chart(fig3, use_container_width=True)

        # small insight based on actual data
        on_time = df_delivery[df_delivery["status"] == "On Time"]["avg_review"].values
        late = df_delivery[df_delivery["status"] == "Late"]["avg_review"].values
        if len(on_time) > 0 and len(late) > 0:
            diff = float(on_time[0]) - float(late[0])
            st.info(
                f"On-time deliveries score {diff:.2f} points higher on average than late ones. "
                f"Delivery speed has a clear impact on customer satisfaction."
            )