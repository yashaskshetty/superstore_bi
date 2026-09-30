OPTIONS (SKIP=1, ERRORS=50, ROWS=1000)
LOAD DATA
CHARACTERSET WE8MSWIN1252
INFILE 'C:\Users\Yashas\OneDrive\Desktop\projects\Sample - Superstore.csv'
BADFILE  'C:\Users\Yashas\OneDrive\Desktop\projects\superstore_bi\oracle\staging.bad'
DISCARDFILE 'C:\Users\Yashas\OneDrive\Desktop\projects\superstore_bi\oracle\staging.dsc'
TRUNCATE INTO TABLE stg_superstore_raw
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
( row_id, order_id, order_date, ship_date, ship_mode,
  customer_id, customer_name, segment,
  country, city, state, postal_code, region,
  product_id, category, sub_category, product_name CHAR(400),
  sales, quantity, discount, profit )
