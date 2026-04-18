# Query Performance Tuning Report

##  Queries Overview
 
Three queries were written against the olist database to answer threee distinct busines questions. 


Seller Geographic Reach was the most complex query that was selected for profiling.
- Chains two CTEs where the second depends on the first
- Applies two independent RANK() window functions simultaneously
- Joins three large tables (order_items, orders, customers)
- Enforces a HAVING filter after aggregation
- Computes a derived efficiency_gap metric in the final SELECT


##  Query Walkthrough

**CTE 1 — shipping_footprint**
Joins order_items to orders and customers. Groups by seller_id to compute how
many distinct customer states each seller ships to, their total orders, total
revenue, and average order value. Filters to delivered orders with at least 3
orders per seller to remove noise.

**CTE 2 — ranked_sellers**
Takes the output of shipping_footprint and applies two independent RANK() window
functions — geo_rank (by states reached) and rev_rank (by total revenue).
Classifies each seller as local, regional, or national using CASE WHEN.

**Final SELECT**
Joins to the sellers table for city and state information. Computes
efficiency_gap = rev_rank - geo_rank. A positive value means the seller reaches
many states but earns less than expected (underperforming geographically). A
negative value means the seller earns more than their reach suggests (efficient).


## Baseline Profiling — Before Indexing

Seq Scan on sellers    (cost=0.00..63.95 rows=3095)
Planning Time:  77.124 ms
Execution Time: 780.787 ms

Seq Scan made PostgreSQL go through every single row of the table before applying any filter or join 
condition. Resulting in a longer execution time.

##  Root Cause Analysis

The major bottleneck was the sequential scan of order items. The query groups
by seller id and meets on order id- no index on these two columns. It had to
read 112,650 rows, compute the entire aggregation on each of the sellers, and only
then filter the HAVING to eliminate those sellers that have less than 3 orders.

The orders table was the second bottleneck. The WHERE clause filters by.
order_status = delivered and is joined on order_id and customer id. Without
a composite index of all three columns, PostgreSQL did another complete.
1 scan of 99,441 rows only to find delivered orders.

Collectively these two sequential scans contributed most of the 780ms execution 
time. The window function (RANK) and the last JOIN to sellers are not bottlenecks,
they act on the existing result set that has been reduced
finished in less than 1ms each.

## Optimization Strategy

Two composite indexes were added targeting the exact bottleneck columns:


CREATE INDEX IF NOT EXISTS idx_oi_seller_order
ON order_items(seller_id,order_id);

CREATE INDEX IF NOT EXISTS idx_ord_status_customer
ON orders(order_status,order_id,customer_id);

Composite indexes were adopted instead of single column indexes since the query includes
multiple column indexes. Indexing allows PostgreSQL to solve the GROUP BY, JOIN and WHERE 
all in one execution, instead of multiple separate operations.

## Post-Optimization Profiling — After Indexing

Index Scan

Planning Time:  8.291 ms
Execution Time: 315.106 ms

##  Results Summary

| Metric         | Before     | After      | Improvement  |

| Execution Time | 780.787 ms | 315.106 ms | 59.6% faster |
| Planning Time  | 77.124 ms  | 8.291 ms   | 89.3% faster |

