set feedback off linesize 180 pagesize 500

prompt ==================================================================
prompt  A. Star-join across 4 dimensions - execution plan
prompt ==================================================================
EXPLAIN PLAN SET STATEMENT_ID='star_join' FOR
SELECT p.category, g.region, SUM(f.sales) sales, SUM(f.profit) profit
FROM   fact_sales f
JOIN   dim_product p   ON p.product_key = f.product_key
JOIN   dim_geography g ON g.geo_key     = f.geo_key
JOIN   dim_date d      ON d.date_key    = f.order_date_key
WHERE  d.cal_year = 2017
GROUP  BY p.category, g.region;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'star_join','TYPICAL'));

prompt ==================================================================
prompt  B. Same filter WITHOUT the indexed column - forces a full scan
prompt ==================================================================
EXPLAIN PLAN SET STATEMENT_ID='no_index' FOR
SELECT COUNT(*) FROM fact_sales WHERE TO_CHAR(order_date_key) LIKE '2017%';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'no_index','BASIC +COST +ROWS'));

prompt ==================================================================
prompt  C. Sargable rewrite of B - index range scan instead
prompt ==================================================================
EXPLAIN PLAN SET STATEMENT_ID='with_index' FOR
SELECT COUNT(*) FROM fact_sales WHERE order_date_key BETWEEN 20170101 AND 20171231;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'with_index','BASIC +COST +ROWS'));

prompt ==================================================================
prompt  D. Index inventory
prompt ==================================================================
col index_name for a26
col cols for a44
SELECT i.index_name, i.index_type, i.uniqueness,
       LISTAGG(c.column_name, ', ') WITHIN GROUP (ORDER BY c.column_position) cols
FROM   user_indexes i JOIN user_ind_columns c ON c.index_name = i.index_name
WHERE  i.table_name = 'FACT_SALES'
GROUP  BY i.index_name, i.index_type, i.uniqueness ORDER BY i.index_name;
exit
