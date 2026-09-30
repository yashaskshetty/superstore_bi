set serveroutput on
set linesize 170 pagesize 300 feedback off
BEGIN pkg_superstore_etl.p_run_full_load; END;
/
prompt === ETL RUN LOG ===
col step_name for a20
col message for a46
col status for a8
SELECT run_id, step_name, rows_loaded, rows_rejected, status,
       TO_CHAR(finished_at - started_at) elapsed, message
FROM etl_run_log ORDER BY run_id;

prompt === ROW COUNTS ===
SELECT 'dim_date' t, COUNT(*) n FROM dim_date
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_geography', COUNT(*) FROM dim_geography
UNION ALL SELECT 'dim_product', COUNT(*) FROM dim_product
UNION ALL SELECT 'fact_sales', COUNT(*) FROM fact_sales
UNION ALL SELECT 'etl_reject_log', COUNT(*) FROM etl_reject_log;

prompt === TOTALS (must match the SQLite build) ===
SELECT TO_CHAR(SUM(sales),'9,999,999.99') total_sales,
       TO_CHAR(SUM(profit),'9,999,999.99') total_profit,
       pkg_superstore_etl.fn_margin_pct(SUM(profit),SUM(sales)) margin_pct
FROM fact_sales;

prompt === DISCOUNT BAND MARGIN (PL/SQL function in a GROUP BY) ===
SELECT pkg_superstore_etl.fn_discount_band(discount) band,
       COUNT(*) line_items,
       TO_CHAR(SUM(sales),'9,999,999') sales,
       TO_CHAR(SUM(profit),'9,999,999') profit,
       pkg_superstore_etl.fn_margin_pct(SUM(profit),SUM(sales)) margin_pct
FROM fact_sales
GROUP BY pkg_superstore_etl.fn_discount_band(discount)
ORDER BY MIN(discount);
exit
