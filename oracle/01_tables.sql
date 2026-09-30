-- ============================================================
-- 01_tables.sql   run as: superstore/superstore
-- Staging table, star schema, sequences, audit/reject logs.
-- ============================================================
set echo off feedback on

-- ---------- staging: everything arrives as text, validated later
CREATE TABLE stg_superstore_raw (
  row_id        VARCHAR2(20),
  order_id      VARCHAR2(30),
  order_date    VARCHAR2(20),
  ship_date     VARCHAR2(20),
  ship_mode     VARCHAR2(40),
  customer_id   VARCHAR2(30),
  customer_name VARCHAR2(120),
  segment       VARCHAR2(40),
  country       VARCHAR2(60),
  city          VARCHAR2(80),
  state         VARCHAR2(80),
  postal_code   VARCHAR2(20),
  region        VARCHAR2(40),
  product_id    VARCHAR2(40),
  category      VARCHAR2(60),
  sub_category  VARCHAR2(60),
  product_name  VARCHAR2(400),
  sales         VARCHAR2(40),
  quantity      VARCHAR2(20),
  discount      VARCHAR2(20),
  profit        VARCHAR2(40)
);

-- ---------- dimensions
CREATE TABLE dim_date (
  date_key    NUMBER(8)   CONSTRAINT pk_dim_date PRIMARY KEY,
  full_date   DATE        NOT NULL CONSTRAINT uq_dim_date_dt UNIQUE,
  cal_year    NUMBER(4)   NOT NULL,
  cal_quarter NUMBER(1)   NOT NULL CONSTRAINT ck_dim_date_q CHECK (cal_quarter BETWEEN 1 AND 4),
  cal_month   NUMBER(2)   NOT NULL CONSTRAINT ck_dim_date_m CHECK (cal_month BETWEEN 1 AND 12),
  month_name  VARCHAR2(12) NOT NULL,
  cal_day     NUMBER(2)   NOT NULL,
  day_name    VARCHAR2(12) NOT NULL,
  year_month  VARCHAR2(7) NOT NULL
);

CREATE TABLE dim_customer (
  customer_key  NUMBER(10) CONSTRAINT pk_dim_customer PRIMARY KEY,
  customer_id   VARCHAR2(30)  NOT NULL CONSTRAINT uq_dim_cust_id UNIQUE,
  customer_name VARCHAR2(120) NOT NULL,
  segment       VARCHAR2(40)  NOT NULL
    CONSTRAINT ck_dim_cust_seg CHECK (segment IN ('Consumer','Corporate','Home Office'))
);

CREATE TABLE dim_geography (
  geo_key     NUMBER(10) CONSTRAINT pk_dim_geo PRIMARY KEY,
  country     VARCHAR2(60) NOT NULL,
  region      VARCHAR2(40) NOT NULL,
  state       VARCHAR2(80) NOT NULL,
  city        VARCHAR2(80) NOT NULL,
  postal_code VARCHAR2(20),
  CONSTRAINT uq_dim_geo UNIQUE (country, region, state, city, postal_code)
);

CREATE TABLE dim_product (
  product_key  NUMBER(10) CONSTRAINT pk_dim_product PRIMARY KEY,
  product_id   VARCHAR2(40)  NOT NULL,
  category     VARCHAR2(60)  NOT NULL,
  sub_category VARCHAR2(60)  NOT NULL,
  product_name VARCHAR2(400) NOT NULL,
  CONSTRAINT uq_dim_product UNIQUE (product_id, product_name)
);

-- ---------- fact
CREATE TABLE fact_sales (
  sales_key      NUMBER(10) CONSTRAINT pk_fact_sales PRIMARY KEY,
  order_id       VARCHAR2(30) NOT NULL,
  order_date_key NUMBER(8)  NOT NULL,
  ship_date_key  NUMBER(8)  NOT NULL,
  customer_key   NUMBER(10) NOT NULL,
  product_key    NUMBER(10) NOT NULL,
  geo_key        NUMBER(10) NOT NULL,
  ship_mode      VARCHAR2(40) NOT NULL,
  sales          NUMBER(12,4) NOT NULL CONSTRAINT ck_fact_sales_pos CHECK (sales >= 0),
  quantity       NUMBER(6)    NOT NULL CONSTRAINT ck_fact_qty_pos   CHECK (quantity > 0),
  discount       NUMBER(5,4)  NOT NULL CONSTRAINT ck_fact_disc      CHECK (discount BETWEEN 0 AND 1),
  profit         NUMBER(12,4) NOT NULL,
  ship_days      NUMBER(5)    NOT NULL CONSTRAINT ck_fact_shipdays  CHECK (ship_days >= 0),
  load_ts        DATE DEFAULT SYSDATE NOT NULL,
  CONSTRAINT fk_fact_orderdate FOREIGN KEY (order_date_key) REFERENCES dim_date(date_key),
  CONSTRAINT fk_fact_shipdate  FOREIGN KEY (ship_date_key)  REFERENCES dim_date(date_key),
  CONSTRAINT fk_fact_customer  FOREIGN KEY (customer_key)   REFERENCES dim_customer(customer_key),
  CONSTRAINT fk_fact_product   FOREIGN KEY (product_key)    REFERENCES dim_product(product_key),
  CONSTRAINT fk_fact_geo       FOREIGN KEY (geo_key)        REFERENCES dim_geography(geo_key)
);

-- ---------- operational logging (JD: validation, documentation, monitoring)
CREATE TABLE etl_run_log (
  run_id       NUMBER(10) CONSTRAINT pk_etl_run PRIMARY KEY,
  step_name    VARCHAR2(60) NOT NULL,
  started_at   TIMESTAMP    NOT NULL,
  finished_at  TIMESTAMP,
  rows_loaded  NUMBER(10),
  rows_rejected NUMBER(10),
  status       VARCHAR2(20) CONSTRAINT ck_etl_status CHECK (status IN ('RUNNING','SUCCESS','FAILED')),
  message      VARCHAR2(4000)
);

CREATE TABLE etl_reject_log (
  reject_id  NUMBER(10) CONSTRAINT pk_etl_reject PRIMARY KEY,
  run_id     NUMBER(10),
  source_row VARCHAR2(20),
  reason     VARCHAR2(200) NOT NULL,
  raw_data   VARCHAR2(1000),
  logged_at  DATE DEFAULT SYSDATE NOT NULL
);

-- ---------- sequences (surrogate key generation)
CREATE SEQUENCE seq_customer_key  START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_geo_key       START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_product_key   START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_sales_key     START WITH 1 INCREMENT BY 1 CACHE 100;
CREATE SEQUENCE seq_etl_run       START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_etl_reject    START WITH 1 INCREMENT BY 1 CACHE 50;

SELECT object_type, COUNT(*) FROM user_objects GROUP BY object_type ORDER BY 1;
exit
