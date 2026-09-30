DROP VIEW IF EXISTS v_sales_report;
CREATE VIEW v_sales_report AS
SELECT f.sales_key, f.order_id, d.full_date AS order_date, d.year, d.quarter,
       d.month, d.month_name, d.year_month, sd.full_date AS ship_date, f.ship_days, f.ship_mode,
       c.customer_name, c.segment, g.region, g.state, g.city,
       p.category, p.sub_category, p.product_name,
       f.sales, f.quantity, f.discount, f.profit,
       ROUND(f.profit / NULLIF(f.sales,0) * 100, 2) AS margin_pct
FROM fact_sales f
JOIN dim_date d      ON d.date_key = f.order_date_key
JOIN dim_date sd     ON sd.date_key = f.ship_date_key
JOIN dim_customer c  ON c.customer_key = f.customer_key
JOIN dim_geography g ON g.geo_key = f.geo_key
JOIN dim_product p   ON p.product_key = f.product_key;

DROP VIEW IF EXISTS v_monthly_trend;
CREATE VIEW v_monthly_trend AS
SELECT d.year_month, d.year, d.month,
       ROUND(SUM(f.sales),2) AS sales, ROUND(SUM(f.profit),2) AS profit,
       COUNT(DISTINCT f.order_id) AS orders,
       ROUND(SUM(f.sales)/COUNT(DISTINCT f.order_id),2) AS avg_order_value
FROM fact_sales f JOIN dim_date d ON d.date_key=f.order_date_key
GROUP BY d.year_month, d.year, d.month;

DROP VIEW IF EXISTS v_category_performance;
CREATE VIEW v_category_performance AS
SELECT p.category, p.sub_category,
       ROUND(SUM(f.sales),2) AS sales, ROUND(SUM(f.profit),2) AS profit,
       ROUND(SUM(f.profit)/SUM(f.sales)*100,2) AS margin_pct,
       SUM(f.quantity) AS units,
       RANK() OVER (ORDER BY SUM(f.sales) DESC) AS sales_rank,
       RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.profit) ASC) AS worst_profit_in_cat
FROM fact_sales f JOIN dim_product p ON p.product_key=f.product_key
GROUP BY p.category, p.sub_category;

DROP VIEW IF EXISTS v_discount_impact;
CREATE VIEW v_discount_impact AS
SELECT CASE WHEN f.discount = 0 THEN '0%'
            WHEN f.discount <= 0.10 THEN '1-10%'
            WHEN f.discount <= 0.20 THEN '11-20%'
            WHEN f.discount <= 0.30 THEN '21-30%'
            WHEN f.discount <= 0.50 THEN '31-50%'
            ELSE '>50%' END AS discount_band,
       COUNT(*) AS line_items,
       ROUND(SUM(f.sales),2) AS sales, ROUND(SUM(f.profit),2) AS profit,
       ROUND(SUM(f.profit)/SUM(f.sales)*100,2) AS margin_pct
FROM fact_sales f GROUP BY discount_band;

DROP VIEW IF EXISTS v_top_customers;
CREATE VIEW v_top_customers AS
WITH totals AS (
  SELECT c.customer_name, c.segment,
         ROUND(SUM(f.sales),2) AS sales, ROUND(SUM(f.profit),2) AS profit,
         COUNT(DISTINCT f.order_id) AS orders,
         MAX(d.full_date) AS last_order
  FROM fact_sales f JOIN dim_customer c ON c.customer_key=f.customer_key
  JOIN dim_date d ON d.date_key=f.order_date_key
  GROUP BY c.customer_name, c.segment)
SELECT *, RANK() OVER (ORDER BY sales DESC) AS sales_rank,
       ROUND(sales * 100.0 / (SELECT SUM(sales) FROM totals),2) AS pct_of_revenue
FROM totals;

DROP VIEW IF EXISTS v_shipping_performance;
CREATE VIEW v_shipping_performance AS
SELECT f.ship_mode, COUNT(*) AS shipments,
       ROUND(AVG(f.ship_days),2) AS avg_ship_days,
       MAX(f.ship_days) AS max_ship_days,
       ROUND(SUM(CASE WHEN f.ship_days > 5 THEN 1 ELSE 0 END)*100.0/COUNT(*),2) AS pct_over_5_days
FROM fact_sales f GROUP BY f.ship_mode;
