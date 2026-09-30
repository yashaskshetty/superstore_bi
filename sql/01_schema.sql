CREATE TABLE dim_customer(
  customer_key INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id  TEXT NOT NULL UNIQUE,
  customer_name TEXT NOT NULL,
  segment      TEXT NOT NULL CHECK(segment IN ('Consumer','Corporate','Home Office')));

CREATE TABLE sqlite_sequence(name,seq);

CREATE TABLE dim_geography(
  geo_key INTEGER PRIMARY KEY AUTOINCREMENT,
  country TEXT NOT NULL, region TEXT NOT NULL, state TEXT NOT NULL,
  city TEXT NOT NULL, postal_code TEXT,
  UNIQUE(country,region,state,city,postal_code));

CREATE TABLE dim_product(
  product_key INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id TEXT NOT NULL, category TEXT NOT NULL, sub_category TEXT NOT NULL,
  product_name TEXT NOT NULL, UNIQUE(product_id,product_name));

CREATE TABLE dim_date(
  date_key INTEGER PRIMARY KEY, full_date TEXT NOT NULL UNIQUE,
  year INTEGER NOT NULL, quarter INTEGER NOT NULL, month INTEGER NOT NULL,
  month_name TEXT NOT NULL, day INTEGER NOT NULL, day_name TEXT NOT NULL,
  year_month TEXT NOT NULL);

CREATE TABLE fact_sales(
  sales_key INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id TEXT NOT NULL,
  order_date_key INTEGER NOT NULL REFERENCES dim_date(date_key),
  ship_date_key  INTEGER NOT NULL REFERENCES dim_date(date_key),
  customer_key INTEGER NOT NULL REFERENCES dim_customer(customer_key),
  product_key  INTEGER NOT NULL REFERENCES dim_product(product_key),
  geo_key      INTEGER NOT NULL REFERENCES dim_geography(geo_key),
  ship_mode TEXT NOT NULL,
  sales REAL NOT NULL CHECK(sales >= 0),
  quantity INTEGER NOT NULL CHECK(quantity > 0),
  discount REAL NOT NULL CHECK(discount BETWEEN 0 AND 1),
  profit REAL NOT NULL,
  ship_days INTEGER NOT NULL CHECK(ship_days >= 0));

CREATE INDEX idx_fact_order_date ON fact_sales(order_date_key);

CREATE INDEX idx_fact_product   ON fact_sales(product_key);

CREATE INDEX idx_fact_customer  ON fact_sales(customer_key);

CREATE INDEX idx_fact_geo       ON fact_sales(geo_key);

CREATE TABLE etl_rejects(row_num INTEGER, reason TEXT, raw TEXT);
