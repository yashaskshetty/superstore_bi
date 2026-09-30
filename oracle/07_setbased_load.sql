-- ============================================================
-- 07_setbased_load.sql
-- The Oracle-idiomatic alternative to the row-by-row fact load
-- in pkg_superstore_etl.p_load_fact_sales.
--
-- Trade-off, stated deliberately:
--   * p_load_fact_sales (PL/SQL loop) - explicit per-row reject
--     reasons, easy to read, ~9,994 context switches.
--   * p_load_fact_setbased (below)    - one SQL statement, DML
--     error logging via DBMS_ERRLOG, far faster at volume, but
--     reject reasons are Oracle error codes rather than English.
-- Use the loop while rules are still changing; use set-based at volume.
-- ============================================================
set feedback off linesize 180 pagesize 200

-- error-log table shadowing fact_sales (created once)
DECLARE v_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM user_tables WHERE table_name = 'ERR$_FACT_SALES';
  IF v_cnt = 0 THEN
    DBMS_ERRLOG.CREATE_ERROR_LOG(dml_table_name => 'FACT_SALES');
  END IF;
END;
/

CREATE OR REPLACE PROCEDURE p_load_fact_setbased AS
  v_loaded NUMBER; v_rejected NUMBER; v_run NUMBER;
BEGIN
  SELECT seq_etl_run.NEXTVAL INTO v_run FROM dual;
  INSERT INTO etl_run_log (run_id, step_name, started_at, status)
  VALUES (v_run, 'LOAD_FACT_SETBASED', SYSTIMESTAMP, 'RUNNING');
  COMMIT;

  DELETE FROM fact_sales;
  EXECUTE IMMEDIATE 'TRUNCATE TABLE err$_fact_sales';

  INSERT INTO fact_sales
      (sales_key, order_id, order_date_key, ship_date_key, customer_key,
       product_key, geo_key, ship_mode, sales, quantity, discount, profit, ship_days)
  SELECT seq_sales_key.NEXTVAL,
         TRIM(s.order_id),
         TO_NUMBER(TO_CHAR(pkg_superstore_etl.fn_parse_date(s.order_date),'YYYYMMDD')),
         TO_NUMBER(TO_CHAR(pkg_superstore_etl.fn_parse_date(s.ship_date),'YYYYMMDD')),
         c.customer_key, p.product_key, g.geo_key, TRIM(s.ship_mode),
         pkg_superstore_etl.fn_to_number(s.sales),
         pkg_superstore_etl.fn_to_number(s.quantity),
         pkg_superstore_etl.fn_to_number(s.discount),
         pkg_superstore_etl.fn_to_number(s.profit),
         pkg_superstore_etl.fn_parse_date(s.ship_date) - pkg_superstore_etl.fn_parse_date(s.order_date)
  FROM   stg_superstore_raw s
  JOIN   dim_customer  c ON c.customer_id = TRIM(s.customer_id)
  JOIN   dim_product   p ON p.product_id  = TRIM(s.product_id)
                        AND p.product_name = TRIM(s.product_name)
  JOIN   dim_geography g ON g.country = TRIM(s.country) AND g.region = TRIM(s.region)
                        AND g.state   = TRIM(s.state)   AND g.city   = TRIM(s.city)
                        AND NVL(g.postal_code,'~') = NVL(TRIM(s.postal_code),'~')
  WHERE  pkg_superstore_etl.fn_parse_date(s.order_date) IS NOT NULL
    AND  pkg_superstore_etl.fn_parse_date(s.ship_date)  IS NOT NULL
    AND  pkg_superstore_etl.fn_parse_date(s.ship_date) >= pkg_superstore_etl.fn_parse_date(s.order_date)
  LOG ERRORS INTO err$_fact_sales ('setbased_load') REJECT LIMIT UNLIMITED;

  v_loaded := SQL%ROWCOUNT;
  SELECT COUNT(*) INTO v_rejected FROM err$_fact_sales;
  COMMIT;

  UPDATE etl_run_log
     SET finished_at = SYSTIMESTAMP, rows_loaded = v_loaded,
         rows_rejected = v_rejected, status = 'SUCCESS',
         message = 'single-statement load with DBMS_ERRLOG'
   WHERE run_id = v_run;
  COMMIT;
END p_load_fact_setbased;
/
show errors

prompt === running set-based load ===
BEGIN p_load_fact_setbased; END;
/

prompt === result (must match the row-by-row load exactly) ===
SELECT COUNT(*) AS fact_rows,
       TO_CHAR(SUM(sales),'9,999,999.99')  AS total_sales,
       TO_CHAR(SUM(profit),'9,999,999.99') AS total_profit,
       pkg_superstore_etl.fn_margin_pct(SUM(profit),SUM(sales)) AS margin_pct
FROM   fact_sales;

SELECT COUNT(*) AS dml_errors FROM err$_fact_sales;

col step_name for a22
col message for a40
SELECT run_id, step_name, rows_loaded, rows_rejected, status, message
FROM   etl_run_log WHERE step_name LIKE 'LOAD_FACT%' ORDER BY run_id;
exit
