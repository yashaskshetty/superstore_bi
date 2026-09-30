-- ============================================================
-- 03_package.sql   run as: superstore/superstore
-- PL/SQL package: staging -> star schema, with validation,
-- reject logging and run auditing.
-- ============================================================
set define off

CREATE OR REPLACE PACKAGE pkg_superstore_etl AS
  -- functions
  FUNCTION fn_parse_date   (p_txt IN VARCHAR2) RETURN DATE;
  FUNCTION fn_to_number    (p_txt IN VARCHAR2) RETURN NUMBER;
  FUNCTION fn_discount_band(p_discount IN NUMBER) RETURN VARCHAR2 DETERMINISTIC;
  FUNCTION fn_margin_pct   (p_profit IN NUMBER, p_sales IN NUMBER) RETURN NUMBER DETERMINISTIC;
  -- procedures
  PROCEDURE p_load_dim_date;
  PROCEDURE p_load_dim_customer;
  PROCEDURE p_load_dim_geography;
  PROCEDURE p_load_dim_product;
  PROCEDURE p_load_fact_sales;
  PROCEDURE p_run_full_load;
END pkg_superstore_etl;
/

CREATE OR REPLACE PACKAGE BODY pkg_superstore_etl AS

  g_run_id NUMBER;

  -- ---------- private helpers ----------
  PROCEDURE log_start (p_step VARCHAR2) IS
  BEGIN
    SELECT seq_etl_run.NEXTVAL INTO g_run_id FROM dual;
    INSERT INTO etl_run_log (run_id, step_name, started_at, status)
    VALUES (g_run_id, p_step, SYSTIMESTAMP, 'RUNNING');
    COMMIT;
  END log_start;

  PROCEDURE log_end (p_loaded NUMBER, p_rejected NUMBER, p_msg VARCHAR2 DEFAULT NULL) IS
  BEGIN
    UPDATE etl_run_log
       SET finished_at = SYSTIMESTAMP, rows_loaded = p_loaded,
           rows_rejected = p_rejected, status = 'SUCCESS', message = p_msg
     WHERE run_id = g_run_id;
    COMMIT;
  END log_end;

  PROCEDURE log_fail (p_msg VARCHAR2) IS
  BEGIN
    UPDATE etl_run_log
       SET finished_at = SYSTIMESTAMP, status = 'FAILED', message = SUBSTR(p_msg,1,4000)
     WHERE run_id = g_run_id;
    COMMIT;
  END log_fail;

  PROCEDURE log_reject (p_row VARCHAR2, p_reason VARCHAR2, p_raw VARCHAR2) IS
  BEGIN
    INSERT INTO etl_reject_log (reject_id, run_id, source_row, reason, raw_data)
    VALUES (seq_etl_reject.NEXTVAL, g_run_id, p_row, p_reason, SUBSTR(p_raw,1,1000));
  END log_reject;

  -- ---------- public functions ----------
  FUNCTION fn_parse_date (p_txt IN VARCHAR2) RETURN DATE IS
    v_fmts SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('MM/DD/YYYY','DD-MM-YYYY','YYYY-MM-DD','MM-DD-YYYY');
  BEGIN
    IF p_txt IS NULL THEN RETURN NULL; END IF;
    FOR i IN 1 .. v_fmts.COUNT LOOP
      BEGIN
        RETURN TO_DATE(TRIM(p_txt), v_fmts(i));
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END LOOP;
    RETURN NULL;
  END fn_parse_date;

  FUNCTION fn_to_number (p_txt IN VARCHAR2) RETURN NUMBER IS
  BEGIN
    RETURN TO_NUMBER(TRIM(p_txt));
  EXCEPTION WHEN OTHERS THEN RETURN NULL;
  END fn_to_number;

  FUNCTION fn_discount_band (p_discount IN NUMBER) RETURN VARCHAR2 DETERMINISTIC IS
  BEGIN
    RETURN CASE
             WHEN p_discount IS NULL   THEN 'UNKNOWN'
             WHEN p_discount = 0       THEN '0%'
             WHEN p_discount <= 0.10   THEN '1-10%'
             WHEN p_discount <= 0.20   THEN '11-20%'
             WHEN p_discount <= 0.30   THEN '21-30%'
             WHEN p_discount <= 0.50   THEN '31-50%'
             ELSE '>50%'
           END;
  END fn_discount_band;

  FUNCTION fn_margin_pct (p_profit IN NUMBER, p_sales IN NUMBER) RETURN NUMBER DETERMINISTIC IS
  BEGIN
    IF p_sales IS NULL OR p_sales = 0 THEN RETURN NULL; END IF;
    RETURN ROUND(p_profit / p_sales * 100, 2);
  END fn_margin_pct;

  -- ---------- dimension loads ----------
  PROCEDURE p_load_dim_date IS
    v_min DATE; v_max DATE; v_d DATE; v_n NUMBER := 0;
  BEGIN
    log_start('LOAD_DIM_DATE');
    SELECT MIN(LEAST(fn_parse_date(order_date), fn_parse_date(ship_date))),
           MAX(GREATEST(fn_parse_date(order_date), fn_parse_date(ship_date)))
      INTO v_min, v_max
      FROM stg_superstore_raw
     WHERE fn_parse_date(order_date) IS NOT NULL
       AND fn_parse_date(ship_date)  IS NOT NULL;

    -- contiguous calendar: no gaps, so Power BI time intelligence is correct
    v_d := v_min;
    WHILE v_d <= v_max LOOP
      INSERT INTO dim_date (date_key, full_date, cal_year, cal_quarter, cal_month,
                            month_name, cal_day, day_name, year_month)
      VALUES (TO_NUMBER(TO_CHAR(v_d,'YYYYMMDD')), v_d,
              TO_NUMBER(TO_CHAR(v_d,'YYYY')), TO_NUMBER(TO_CHAR(v_d,'Q')),
              TO_NUMBER(TO_CHAR(v_d,'MM')), TRIM(TO_CHAR(v_d,'Month','NLS_DATE_LANGUAGE=ENGLISH')),
              TO_NUMBER(TO_CHAR(v_d,'DD')), TRIM(TO_CHAR(v_d,'Day','NLS_DATE_LANGUAGE=ENGLISH')),
              TO_CHAR(v_d,'YYYY-MM'));
      v_n := v_n + 1;
      v_d := v_d + 1;
    END LOOP;
    COMMIT;
    log_end(v_n, 0, 'calendar '||TO_CHAR(v_min,'YYYY-MM-DD')||' to '||TO_CHAR(v_max,'YYYY-MM-DD'));
  EXCEPTION WHEN OTHERS THEN log_fail(SQLERRM); RAISE;
  END p_load_dim_date;

  PROCEDURE p_load_dim_customer IS v_n NUMBER;
  BEGIN
    log_start('LOAD_DIM_CUSTOMER');
    INSERT INTO dim_customer (customer_key, customer_id, customer_name, segment)
    SELECT seq_customer_key.NEXTVAL, customer_id, customer_name, segment
      FROM (SELECT DISTINCT TRIM(customer_id) customer_id,
                   TRIM(customer_name) customer_name, TRIM(segment) segment
              FROM stg_superstore_raw
             WHERE customer_id IS NOT NULL
               AND TRIM(segment) IN ('Consumer','Corporate','Home Office'));
    v_n := SQL%ROWCOUNT; COMMIT; log_end(v_n, 0);
  EXCEPTION WHEN OTHERS THEN log_fail(SQLERRM); RAISE;
  END p_load_dim_customer;

  PROCEDURE p_load_dim_geography IS v_n NUMBER;
  BEGIN
    log_start('LOAD_DIM_GEOGRAPHY');
    INSERT INTO dim_geography (geo_key, country, region, state, city, postal_code)
    SELECT seq_geo_key.NEXTVAL, country, region, state, city, postal_code
      FROM (SELECT DISTINCT TRIM(country) country, TRIM(region) region, TRIM(state) state,
                   TRIM(city) city, TRIM(postal_code) postal_code
              FROM stg_superstore_raw WHERE country IS NOT NULL);
    v_n := SQL%ROWCOUNT; COMMIT; log_end(v_n, 0);
  EXCEPTION WHEN OTHERS THEN log_fail(SQLERRM); RAISE;
  END p_load_dim_geography;

  PROCEDURE p_load_dim_product IS v_n NUMBER;
  BEGIN
    log_start('LOAD_DIM_PRODUCT');
    INSERT INTO dim_product (product_key, product_id, category, sub_category, product_name)
    SELECT seq_product_key.NEXTVAL, product_id, category, sub_category, product_name
      FROM (SELECT DISTINCT TRIM(product_id) product_id, TRIM(category) category,
                   TRIM(sub_category) sub_category, TRIM(product_name) product_name
              FROM stg_superstore_raw WHERE product_id IS NOT NULL);
    v_n := SQL%ROWCOUNT; COMMIT; log_end(v_n, 0);
  EXCEPTION WHEN OTHERS THEN log_fail(SQLERRM); RAISE;
  END p_load_dim_product;

  -- ---------- fact load: row-by-row so bad rows are logged, not fatal ----------
  PROCEDURE p_load_fact_sales IS
    v_ok NUMBER := 0; v_bad NUMBER := 0;
    v_od DATE; v_sd DATE;
    v_sales NUMBER; v_qty NUMBER; v_disc NUMBER; v_profit NUMBER;
    v_ck NUMBER; v_pk NUMBER; v_gk NUMBER;
  BEGIN
    log_start('LOAD_FACT_SALES');
    FOR r IN (SELECT * FROM stg_superstore_raw) LOOP
      BEGIN
        v_od := fn_parse_date(r.order_date);
        v_sd := fn_parse_date(r.ship_date);
        v_sales  := fn_to_number(r.sales);
        v_qty    := fn_to_number(r.quantity);
        v_disc   := fn_to_number(r.discount);
        v_profit := fn_to_number(r.profit);

        IF v_od IS NULL OR v_sd IS NULL THEN
          log_reject(r.row_id,'unparseable order or ship date', r.order_date||'|'||r.ship_date);
          v_bad := v_bad + 1; CONTINUE;
        ELSIF v_sd < v_od THEN
          log_reject(r.row_id,'ship date before order date', r.order_date||'|'||r.ship_date);
          v_bad := v_bad + 1; CONTINUE;
        ELSIF v_sales IS NULL OR v_qty IS NULL OR v_disc IS NULL OR v_profit IS NULL THEN
          log_reject(r.row_id,'non-numeric measure', r.sales||'|'||r.quantity||'|'||r.discount||'|'||r.profit);
          v_bad := v_bad + 1; CONTINUE;
        ELSIF v_qty <= 0 THEN
          log_reject(r.row_id,'non-positive quantity', r.quantity);
          v_bad := v_bad + 1; CONTINUE;
        ELSIF v_disc < 0 OR v_disc > 1 THEN
          log_reject(r.row_id,'discount outside 0-1', r.discount);
          v_bad := v_bad + 1; CONTINUE;
        END IF;

        SELECT customer_key INTO v_ck FROM dim_customer WHERE customer_id = TRIM(r.customer_id);
        SELECT product_key  INTO v_pk FROM dim_product
         WHERE product_id = TRIM(r.product_id) AND product_name = TRIM(r.product_name);
        SELECT geo_key INTO v_gk FROM dim_geography
         WHERE country = TRIM(r.country) AND region = TRIM(r.region) AND state = TRIM(r.state)
           AND city = TRIM(r.city)
           AND NVL(postal_code,'~') = NVL(TRIM(r.postal_code),'~');

        INSERT INTO fact_sales (sales_key, order_id, order_date_key, ship_date_key,
                                customer_key, product_key, geo_key, ship_mode,
                                sales, quantity, discount, profit, ship_days)
        VALUES (seq_sales_key.NEXTVAL, TRIM(r.order_id),
                TO_NUMBER(TO_CHAR(v_od,'YYYYMMDD')), TO_NUMBER(TO_CHAR(v_sd,'YYYYMMDD')),
                v_ck, v_pk, v_gk, TRIM(r.ship_mode),
                v_sales, v_qty, v_disc, v_profit, v_sd - v_od);
        v_ok := v_ok + 1;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          log_reject(r.row_id,'dimension lookup failed', r.customer_id||'|'||r.product_id);
          v_bad := v_bad + 1;
        WHEN OTHERS THEN
          log_reject(r.row_id, SUBSTR(SQLERRM,1,200), r.row_id);
          v_bad := v_bad + 1;
      END;
    END LOOP;
    COMMIT;
    log_end(v_ok, v_bad);
  EXCEPTION WHEN OTHERS THEN log_fail(SQLERRM); RAISE;
  END p_load_fact_sales;

  PROCEDURE p_run_full_load IS
  BEGIN
    EXECUTE IMMEDIATE 'DELETE FROM fact_sales';
    EXECUTE IMMEDIATE 'DELETE FROM dim_date';
    EXECUTE IMMEDIATE 'DELETE FROM dim_customer';
    EXECUTE IMMEDIATE 'DELETE FROM dim_geography';
    EXECUTE IMMEDIATE 'DELETE FROM dim_product';
    COMMIT;
    p_load_dim_date;
    p_load_dim_customer;
    p_load_dim_geography;
    p_load_dim_product;
    p_load_fact_sales;
    DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);
  END p_run_full_load;

END pkg_superstore_etl;
/
show errors
SELECT object_name, object_type, status FROM user_objects WHERE object_type LIKE 'PACKAGE%';
exit
