set feedback off linesize 180 pagesize 400

-- ============ indexes on foreign keys (fact table access paths) ============
CREATE INDEX idx_fact_order_date ON fact_sales(order_date_key);
CREATE INDEX idx_fact_ship_date  ON fact_sales(ship_date_key);
CREATE INDEX idx_fact_customer   ON fact_sales(customer_key);
CREATE INDEX idx_fact_product    ON fact_sales(product_key);
CREATE INDEX idx_fact_geo        ON fact_sales(geo_key);
CREATE INDEX idx_fact_order_id   ON fact_sales(order_id);
-- function-based index: supports filtering by discount band without a table scan
CREATE INDEX idx_fact_disc_band  ON fact_sales(pkg_superstore_etl.fn_discount_band(discount));

-- ============ reporting views ============
CREATE OR REPLACE VIEW v_sales_report AS
SELECT f.sales_key, f.order_id, d.full_date AS order_date, d.cal_year, d.cal_quarter,
       d.cal_month, d.month_name, d.year_month, sd.full_date AS ship_date,
       f.ship_days, f.ship_mode,
       c.customer_name, c.segment, g.region, g.state, g.city,
       p.category, p.sub_category, p.product_name,
       f.sales, f.quantity, f.discount, f.profit,
       pkg_superstore_etl.fn_discount_band(f.discount) AS discount_band,
       pkg_superstore_etl.fn_margin_pct(f.profit, f.sales) AS margin_pct
FROM   fact_sales f
JOIN   dim_date      d  ON d.date_key  = f.order_date_key
JOIN   dim_date      sd ON sd.date_key = f.ship_date_key
JOIN   dim_customer  c  ON c.customer_key = f.customer_key
JOIN   dim_geography g  ON g.geo_key      = f.geo_key
JOIN   dim_product   p  ON p.product_key  = f.product_key;

CREATE OR REPLACE VIEW v_monthly_trend AS
SELECT d.year_month, d.cal_year, d.cal_month,
       ROUND(SUM(f.sales),2)  AS sales,
       ROUND(SUM(f.profit),2) AS profit,
       COUNT(DISTINCT f.order_id) AS orders,
       ROUND(SUM(f.sales)/COUNT(DISTINCT f.order_id),2) AS avg_order_value,
       ROUND(AVG(SUM(f.sales)) OVER (ORDER BY d.year_month
             ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),2) AS sales_3m_moving_avg
FROM   fact_sales f JOIN dim_date d ON d.date_key = f.order_date_key
GROUP  BY d.year_month, d.cal_year, d.cal_month;

CREATE OR REPLACE VIEW v_category_performance AS
SELECT p.category, p.sub_category,
       ROUND(SUM(f.sales),2)  AS sales,
       ROUND(SUM(f.profit),2) AS profit,
       pkg_superstore_etl.fn_margin_pct(SUM(f.profit), SUM(f.sales)) AS margin_pct,
       SUM(f.quantity) AS units,
       RANK() OVER (ORDER BY SUM(f.sales) DESC) AS sales_rank,
       RANK() OVER (PARTITION BY p.category ORDER BY SUM(f.profit) ASC) AS worst_profit_in_cat,
       ROUND(RATIO_TO_REPORT(SUM(f.sales)) OVER () * 100, 2) AS pct_of_sales
FROM   fact_sales f JOIN dim_product p ON p.product_key = f.product_key
GROUP  BY p.category, p.sub_category;

CREATE OR REPLACE VIEW v_discount_impact AS
SELECT pkg_superstore_etl.fn_discount_band(f.discount) AS discount_band,
       MIN(f.discount) AS band_floor,
       COUNT(*) AS line_items,
       ROUND(SUM(f.sales),2)  AS sales,
       ROUND(SUM(f.profit),2) AS profit,
       pkg_superstore_etl.fn_margin_pct(SUM(f.profit), SUM(f.sales)) AS margin_pct,
       SUM(CASE WHEN f.profit < 0 THEN 1 ELSE 0 END) AS loss_making_items
FROM   fact_sales f
GROUP  BY pkg_superstore_etl.fn_discount_band(f.discount);

CREATE OR REPLACE VIEW v_top_customers AS
WITH totals AS (
  SELECT c.customer_name, c.segment,
         ROUND(SUM(f.sales),2)  AS sales,
         ROUND(SUM(f.profit),2) AS profit,
         COUNT(DISTINCT f.order_id) AS orders,
         MAX(d.full_date) AS last_order
  FROM   fact_sales f
  JOIN   dim_customer c ON c.customer_key = f.customer_key
  JOIN   dim_date d     ON d.date_key     = f.order_date_key
  GROUP  BY c.customer_name, c.segment)
SELECT t.*,
       RANK() OVER (ORDER BY sales DESC) AS sales_rank,
       ROUND(RATIO_TO_REPORT(sales) OVER () * 100, 2) AS pct_of_revenue,
       ROUND(SUM(sales) OVER (ORDER BY sales DESC) /
             SUM(sales) OVER () * 100, 2) AS cumulative_pct
FROM   totals t;

CREATE OR REPLACE VIEW v_shipping_performance AS
SELECT f.ship_mode, COUNT(*) AS shipments,
       ROUND(AVG(f.ship_days),2) AS avg_ship_days,
       MAX(f.ship_days) AS max_ship_days,
       ROUND(SUM(CASE WHEN f.ship_days > 5 THEN 1 ELSE 0 END) * 100 / COUNT(*), 2) AS pct_over_5_days
FROM   fact_sales f GROUP BY f.ship_mode;

-- ============ synonyms (stable names for the reporting layer) ============
CREATE OR REPLACE SYNONYM syn_sales_report   FOR v_sales_report;
CREATE OR REPLACE SYNONYM syn_monthly_trend  FOR v_monthly_trend;
CREATE OR REPLACE SYNONYM syn_discount_impact FOR v_discount_impact;

BEGIN DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE); END;
/

prompt === OBJECT INVENTORY ===
SELECT object_type, COUNT(*) cnt FROM user_objects GROUP BY object_type ORDER BY 1;

prompt === INVALID OBJECTS (should be none) ===
SELECT object_name, object_type FROM user_objects WHERE status <> 'VALID';
exit
