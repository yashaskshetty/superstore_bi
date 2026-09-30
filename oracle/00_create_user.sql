-- ============================================================
-- 00_create_user.sql   run as: sqlplus / as sysdba
-- Creates the SUPERSTORE schema and grants the privileges the
-- ETL package and reporting layer need.
-- ============================================================
set echo off feedback on

DECLARE
  v_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = 'SUPERSTORE';
  IF v_cnt > 0 THEN
    EXECUTE IMMEDIATE 'DROP USER superstore CASCADE';
    DBMS_OUTPUT.PUT_LINE('dropped existing SUPERSTORE schema');
  END IF;
END;
/

CREATE USER superstore IDENTIFIED BY superstore
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION            TO superstore;
GRANT CREATE TABLE              TO superstore;
GRANT CREATE VIEW               TO superstore;
GRANT CREATE SEQUENCE           TO superstore;
GRANT CREATE PROCEDURE          TO superstore;
GRANT CREATE TRIGGER            TO superstore;
GRANT CREATE SYNONYM            TO superstore;
GRANT CREATE ANY DIRECTORY      TO superstore;
GRANT SELECT ANY DICTIONARY     TO superstore;   -- lets the schema read its own plans
GRANT EXECUTE ON dbms_stats     TO superstore;

-- needed so EXPLAIN PLAN / autotrace work in 07_optimize.sql
GRANT SELECT_CATALOG_ROLE       TO superstore;

SELECT username, account_status, default_tablespace
FROM   dba_users WHERE username = 'SUPERSTORE';
exit
