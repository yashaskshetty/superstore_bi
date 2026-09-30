import csv, sqlite3, os, datetime, re
SRC="/mnt/c/Users/Yashas/OneDrive/Desktop/projects/Sample - Superstore.csv"
DB="/tmp/pbi/superstore.db"
if os.path.exists(DB): os.remove(DB)
con=sqlite3.connect(DB); cur=con.cursor()

cur.executescript("""
PRAGMA foreign_keys=ON;
CREATE TABLE dim_customer(
  customer_key INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id  TEXT NOT NULL UNIQUE,
  customer_name TEXT NOT NULL,
  segment      TEXT NOT NULL CHECK(segment IN ('Consumer','Corporate','Home Office')));
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
""")

def pdate(s):
    for f in ("%m/%d/%Y","%Y-%m-%d","%d-%m-%Y"):
        try: return datetime.datetime.strptime(s.strip(),f).date()
        except ValueError: pass
    return None

cust={};geo={};prod={};dates=set()
rows=[];rejects=[]
with open(SRC,encoding='cp1252',newline='') as f:
    for n,r in enumerate(csv.DictReader(f),start=2):
        od,sd=pdate(r['Order Date']),pdate(r['Ship Date'])
        if not od or not sd: rejects.append((n,'unparseable date',str(r)[:120])); continue
        if sd<od: rejects.append((n,'ship date before order date',str(r)[:120])); continue
        try:
            sales=float(r['Sales']); qty=int(r['Quantity'])
            disc=float(r['Discount']); prof=float(r['Profit'])
        except ValueError: rejects.append((n,'non-numeric measure',str(r)[:120])); continue
        if qty<=0: rejects.append((n,'non-positive quantity',str(r)[:120])); continue
        ck=r['Customer ID'].strip()
        cust.setdefault(ck,(ck,r['Customer Name'].strip(),r['Segment'].strip()))
        gk=(r['Country'].strip(),r['Region'].strip(),r['State'].strip(),r['City'].strip(),r['Postal Code'].strip())
        geo.setdefault(gk,gk)
        pk=(r['Product ID'].strip(),r['Product Name'].strip())
        prod.setdefault(pk,(pk[0],r['Category'].strip(),r['Sub-Category'].strip(),pk[1]))
        dates.add(od); dates.add(sd)
        rows.append((r['Order ID'].strip(),od,sd,ck,pk,gk,r['Ship Mode'].strip(),
                     sales,qty,disc,prof,(sd-od).days))

cur.executemany("INSERT INTO dim_customer(customer_id,customer_name,segment) VALUES(?,?,?)",list(cust.values()))
cur.executemany("INSERT INTO dim_geography(country,region,state,city,postal_code) VALUES(?,?,?,?,?)",list(geo.values()))
cur.executemany("INSERT INTO dim_product(product_id,category,sub_category,product_name) VALUES(?,?,?,?)",list(prod.values()))

# contiguous date dimension across the full range (no gaps -> correct time intelligence)
lo,hi=min(dates),max(dates); dd=[];cd=lo
while cd<=hi:
    dd.append((int(cd.strftime('%Y%m%d')),cd.isoformat(),cd.year,(cd.month-1)//3+1,cd.month,
               cd.strftime('%B'),cd.day,cd.strftime('%A'),cd.strftime('%Y-%m')))
    cd+=datetime.timedelta(days=1)
cur.executemany("INSERT INTO dim_date VALUES(?,?,?,?,?,?,?,?,?)",dd)

ckey={r[0]:r[1] for r in cur.execute("SELECT customer_id,customer_key FROM dim_customer")}
gkey={(a,b,c,d,e):k for a,b,c,d,e,k in cur.execute("SELECT country,region,state,city,postal_code,geo_key FROM dim_geography")}
pkey={(a,b):k for a,b,k in cur.execute("SELECT product_id,product_name,product_key FROM dim_product")}

cur.executemany("""INSERT INTO fact_sales(order_id,order_date_key,ship_date_key,customer_key,
 product_key,geo_key,ship_mode,sales,quantity,discount,profit,ship_days)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",
 [(o,int(od.strftime('%Y%m%d')),int(sd.strftime('%Y%m%d')),ckey[ck],pkey[pk],gkey[gk],sm,s,q,di,pr,shd)
  for o,od,sd,ck,pk,gk,sm,s,q,di,pr,shd in rows])
cur.executemany("INSERT INTO etl_rejects VALUES(?,?,?)",rejects)
con.commit()

print("=== LOAD SUMMARY ===")
for t in ("dim_customer","dim_geography","dim_product","dim_date","fact_sales","etl_rejects"):
    print(" %-14s %6d"%(t,cur.execute("SELECT COUNT(*) FROM "+t).fetchone()[0]))
print(" date range   ", lo, "->", hi)
print(" rejects      ", len(rejects), {r[1] for r in rejects} or '-')
s,p=cur.execute("SELECT ROUND(SUM(sales),2),ROUND(SUM(profit),2) FROM fact_sales").fetchone()
print(" total sales  ", s, "| total profit", p, "| margin %.2f%%"%(100*p/s))
con.close()
