# Superstore BI — Build Guide

You build the Power BI report; everything feeding it is already built. Work top to bottom.

**Time:** ~3 hours for all four pages. Stop after Page 1 if you're short — one strong page is resume-worthy.

---

## What already exists

| Path | What it is |
|---|---|
| `superstore.db` | SQLite star schema — 4 dimensions + 1 fact, 9,994 rows, 0 rejects |
| `sql/01_schema.sql` | DDL: PKs, FKs, CHECK constraints, 4 indexes |
| `sql/02_views.sql` | 6 reporting views (joins, CTEs, window functions, CASE bucketing) |
| `etl/build_database.py` | CSV → star schema loader with row-level validation + reject table |
| `dax/measures.txt` | 28 DAX measures, grouped and ordered |
| `exports/*.csv` | Every view pre-exported — the fallback if ODBC gives you trouble |

**Model shape:**

```
dim_date ──┐
dim_customer ──┤
dim_product ──┼──> fact_sales   (star schema, single-direction filters)
dim_geography ─┘
```

---

## Step 1 — Connect Power BI to the database

### Option A: ODBC (do this one — it's a JD requirement)

The JD asks for *"Configure and maintain ODBC/OLE DB connections, System DSNs, database drivers."* This step **is** that line item. Don't skip it for convenience.

1. Download the SQLite ODBC driver: http://www.ch-werner.de/sqliteodbc/ → `sqliteodbc_w64.exe` (64-bit, to match 64-bit Power BI Desktop).
2. Install it.
3. Open **ODBC Data Sources (64-bit)** from the Start menu.
4. **System DSN** tab → **Add** → *SQLite3 ODBC Driver*.
5. Data Source Name: `SuperstoreBI`
   Database Name: browse to this folder's `superstore.db`
   → OK.
6. In Power BI Desktop: **Get Data → ODBC → SuperstoreBI → Connect**.
7. Select the 5 base tables (`dim_*`, `fact_sales`) and the 6 `v_*` views → **Load**.

> **Bit-depth gotcha:** a 32-bit driver will not appear to 64-bit Power BI. If `SuperstoreBI` isn't listed, you installed the wrong build — this exact failure is worth remembering, it's the kind of connectivity troubleshooting the JD describes.

### Option B: fallback if ODBC blocks you

**Get Data → Text/CSV** on the files in `exports/`. You lose the DB-connectivity story, so treat this as temporary and come back to Option A.

---

## Step 2 — Model setup (5 minutes, do not skip)

1. **Model view.** Confirm relationships: `fact_sales[order_date_key] → dim_date[date_key]`, plus `customer_key`, `product_key`, `geo_key`. Power BI usually auto-detects these; create any that are missing.
2. Every relationship: **many-to-one**, **single** cross-filter direction.
3. Select `dim_date` → **Table tools → Mark as date table** → pick `full_date`.
   *Without this, every time-intelligence measure returns blank.*
4. Hide these from report view (right-click → Hide): all `*_key` columns on `fact_sales`, and `dim_date[date_key]`.

## Step 3 — Add the measures

Open `dax/measures.txt`. For each block: **Modeling → New Measure**, paste, Enter. Create them in file order — section 3 and 4 reference section 1. Apply the formatting listed at the bottom of the file.

---

## Step 4 — Build four pages

### Page 1 — Executive Overview
- **KPI cards (row across top):** Total Sales · Total Profit · Profit Margin % · Total Orders · Avg Order Value
- **Line chart:** `dim_date[year_month]` on X, `Total Sales` and `Sales LY` as two lines → shows YoY at a glance
- **Bar chart:** `dim_product[category]` by `Total Sales`, `Profit Margin %` as tooltip
- **Map:** `dim_geography[state]`, bubble size = `Total Sales`
- **Slicers:** `dim_date[year]`, `dim_geography[region]`, `dim_customer[segment]`

### Page 2 — Discount & Profitability  ← *the page that makes this project interesting*
- **Column + line combo:** `v_discount_impact[discount_band]` on X, `sales` as columns, `margin_pct` as line. The line crosses zero between the 11–20% and 21–30% bands — that's the finding.
- **Cards:** Loss-Making Line Items · % Loss-Making Items · Loss Amount · Margin Lost to Discounting
- **Scatter:** `Avg Discount` (X) vs `Profit Margin %` (Y), one point per `sub_category`, bubble = `Total Sales`
- **Table:** sub-category with `Total Sales`, `Total Profit`, `Profit Margin %`, conditional-formatted red where margin < 0

### Page 3 — Product & Customer
- **Table:** sub-category by `Total Sales`, `Product Sales Rank`, `% of Total Sales`
- **Bar:** top 10 customers by `Total Sales` (Top N filter on `Customer Sales Rank`)
- **Card:** Top 20 Customer Revenue % — answers "are we dependent on a few accounts?"
- **Treemap:** category → sub-category by sales

### Page 4 — Operations
- **Bar:** `ship_mode` by `Avg Ship Days`
- **Card:** % Shipments Over 5 Days
- **Line:** `Avg Ship Days` by `year_month` — is fulfilment getting slower?
- **Table:** `v_shipping_performance` in full

---

## Step 5 — Findings to write up

Verified against the database — all reproducible from the views:

| Finding | Number |
|---|---|
| Margin at 0% discount | **29.5%** |
| Margin at 11–20% discount | **11.6%** |
| Margin at 21–30% discount | **−10.1%** |
| Margin above 50% discount | **−119.2%** |
| Loss-making line items | **1,871 of 9,994 (18.7%)** |
| Tables sub-category | $206,966 sales, **−$17,725 profit** (−8.6% margin) |
| Standard Class shipments over 5 days | **30.6%** |
| Top 20 customers' share of revenue | **11.5%** (revenue is *not* concentrated) |
| Total | $2,297,201 sales · $286,397 profit · 12.5% margin |

**The recommendation this supports:** cap discounts at 20%. Every band above it is loss-making, and the >50% band loses more money than it brings in revenue. Tables and Bookcases need repricing or delisting.

**Why the last row matters:** because revenue *isn't* concentrated in a few customers, the margin problem is a pricing-policy problem, not an account-management problem. That distinction is the analyst judgement — state it in interviews.

---

## Step 6 — Publish

1. **File → Save as** `superstore_bi.pbix` in this folder.
2. Sign in to Power BI Service with your college account → **Publish** → workspace.
3. Get the report URL for your resume/GitHub.
4. Push this whole folder to GitHub: the `.db`, SQL, ETL, DAX and the `.pbix`. The repo *is* the evidence — a reviewer can see the schema and the SQL, not just a screenshot.
5. Screenshot each page into `screenshots/` and reference them in the repo README.
