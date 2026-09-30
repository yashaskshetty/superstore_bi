# Superstore BI — Oracle Data Warehouse & Power BI Reporting

A retail sales reporting solution built end to end: CSV → SQL\*Loader → staging → PL/SQL transformation → Oracle star schema → SQL reporting views → Power BI dashboard over ODBC.

Built to answer one business question: **where is discounting destroying margin?**

---

## Headline finding

Margin collapses past a 20% discount, and it is not gradual — it inverts.

| Discount band | Line items | Sales | Profit | Margin |
|---|---:|---:|---:|---:|
| 0% | 4,798 | $1,087,908 | $320,988 | **+29.5%** |
| 1–10% | 94 | $54,369 | $9,029 | +16.6% |
| 11–20% | 3,709 | $792,153 | $91,756 | +11.6% |
| 21–30% | 227 | $103,227 | −$10,369 | **−10.1%** |
| 31–50% | 310 | $195,315 | −$48,448 | −24.8% |
| >50% | 856 | $64,229 | −$76,559 | **−119.2%** |

**1,871 of 9,994 line items (18.7%) lose money.** The `>50%` band loses more in absolute profit than it generates in revenue.

Supporting findings:

- **Tables** sub-category: $206,966 sales, **−$17,725 profit** (−8.6% margin). Bookcases and Supplies are also net-negative.
- **30.6%** of Standard Class shipments take more than 5 days.
- The top 20 customers are only **11.5%** of revenue.

**Recommendation:** cap discounts at 20% and reprice or delist Tables and Bookcases.

**Why the concentration figure matters:** because revenue is *not* concentrated in a few accounts, the margin problem is a pricing-policy problem, not an account-management one. That distinction determines who owns the fix.

---

## Architecture

```
Sample - Superstore.csv  (9,994 rows, cp1252)
        │
        ▼  SQL*Loader  (control file, bad/discard files, 0.69s)
   stg_superstore_raw    all columns VARCHAR2 — nothing rejected at the door
        │
        ▼  pkg_superstore_etl  (PL/SQL: validate, conform, surrogate keys)
   ┌────────────────────────────────────────────┐
   │  dim_date  dim_customer  dim_product       │
   │  dim_geography          →  fact_sales      │   star schema
   └────────────────────────────────────────────┘
        │                          │
        │                          └──> etl_run_log / etl_reject_log
        ▼  6 reporting views
   v_sales_report · v_monthly_trend · v_category_performance
   v_discount_impact · v_top_customers · v_shipping_performance
        │
        ▼  ODBC (DSN: OracleSuperstore)
   Power BI Desktop — 4 pages, 29 DAX measures
```

## Database objects

Schema `SUPERSTORE` on Oracle Database 11g XE. All objects `VALID`.

| Type | Count | Notes |
|---|---:|---|
| Tables | 8 | 5 star-schema + 1 staging + 2 operational logs |
| Views | 6 | window functions, `RATIO_TO_REPORT`, CTEs, moving average |
| Indexes | 18 | incl. a **function-based index** on `fn_discount_band(discount)` |
| Sequences | 6 | surrogate key generation |
| Synonyms | 3 | stable names for the reporting layer |
| Packages | 1 | `pkg_superstore_etl` — 4 functions, 6 procedures |

### Integrity built into the schema, not the application

- Primary keys on every table; **5 foreign keys** from `fact_sales` to its dimensions
- `CHECK` constraints: `sales >= 0`, `quantity > 0`, `discount BETWEEN 0 AND 1`, `ship_days >= 0`, segment domain, quarter/month ranges
- `UNIQUE` constraints enforcing dimension grain (e.g. geography on country+region+state+city+postal_code)
- Contiguous `dim_date` calendar (2014-01-03 → 2018-01-05, 1,464 rows, no gaps) so Power BI time intelligence is correct

### Data quality handling

Every row is validated before it reaches the fact table. Failures are **logged, not fatal** — one bad row cannot abort the load:

| Rule | Rejected as |
|---|---|
| Date parses in none of 4 formats | `unparseable order or ship date` |
| Ship date earlier than order date | `ship date before order date` |
| Any measure non-numeric | `non-numeric measure` |
| Quantity ≤ 0 | `non-positive quantity` |
| Discount outside 0–1 | `discount outside 0-1` |
| No matching dimension row | `dimension lookup failed` |

`etl_run_log` records per-step row counts, elapsed time and status; `etl_reject_log` records the offending row and reason.

**Result on this dataset:** 9,994 loaded, **0 rejected**.

---

## Two fact-load implementations

Both are included deliberately, and produce **identical output**.

| | `pkg_superstore_etl.p_load_fact_sales` | `p_load_fact_setbased` |
|---|---|---|
| Approach | PL/SQL cursor loop, row by row | single `INSERT … SELECT` |
| Reject capture | explicit English reasons | `DBMS_ERRLOG` + `LOG ERRORS INTO` |
| Cost | ~9,994 context switches | one statement |
| Best when | rules still changing; readable reasons matter | volume matters |

Both yield 9,994 rows, $2,297,200.86 sales, $286,397.02 profit, 12.47% margin.

The row-by-row version is the "slow-by-slow" anti-pattern at scale — included because its per-row reasons are more useful while validation rules are still being defined, and replaced by the set-based version when throughput matters. Knowing which to reach for is the point.

---

## Query optimisation

`06_optimize.sql` captures real execution plans via `EXPLAIN PLAN` + `DBMS_XPLAN`.

**Non-sargable predicate** — a function on the indexed column:

```sql
SELECT COUNT(*) FROM fact_sales WHERE TO_CHAR(order_date_key) LIKE '2017%';
-- INDEX FAST FULL SCAN | cost 8 | est. 500 rows
```

**Sargable rewrite** — same result, range-scannable:

```sql
SELECT COUNT(*) FROM fact_sales WHERE order_date_key BETWEEN 20170101 AND 20171231;
-- INDEX RANGE SCAN | cost 2 | est. 371 rows
```

**4× cost reduction** from taking the function off the predicate. The four-dimension star join plan is also captured, showing hash joins with `DIM_DATE` filtered first (cost 88).

---

## Cross-engine validation

The same star schema was built independently in SQLite (`etl/build_database.py`, `sql/`) and in Oracle. Both produce, to the cent:

```
9,994 fact rows · $2,297,200.86 sales · $286,397.02 profit · 12.47% margin
```

All six discount bands match. Two independent implementations agreeing is a stronger correctness argument than either alone.

---

## Repository layout

```
oracle/
  00_create_user.sql      schema, tablespace quota, grants
  01_tables.sql           staging, star schema, sequences, log tables
  02_load_staging.ctl     SQL*Loader control file
  03_package.sql          pkg_superstore_etl — functions + procedures
  04_run_load.sql         full load + validation queries
  05_views_indexes.sql    indexes, 6 views, synonyms, stats
  06_optimize.sql         EXPLAIN PLAN / DBMS_XPLAN analysis
  07_setbased_load.sql    set-based load with DBMS_ERRLOG
sql/                      SQLite equivalent (schema + views)
etl/build_database.py     SQLite loader with validation + reject table
dax/measures.txt          29 DAX measures, grouped and ordered
exports/                  every view as CSV (fallback source)
superstore.db             built SQLite database
BUILD_GUIDE.md            step-by-step Power BI build instructions
```

## Reproducing it

Oracle path — run in order as `superstore/superstore` (step 0 as sysdba):

```
sqlplus / as sysdba          @oracle/00_create_user.sql
sqlldr  superstore/superstore control=oracle/02_load_staging.ctl
sqlplus superstore/superstore @oracle/01_tables.sql
sqlplus superstore/superstore @oracle/03_package.sql
sqlplus superstore/superstore @oracle/04_run_load.sql
sqlplus superstore/superstore @oracle/05_views_indexes.sql
```

SQLite path — one command, no server:

```
python etl/build_database.py
```

Power BI: **Get Data → ODBC → `OracleSuperstore`**, then follow `BUILD_GUIDE.md`.

---

## Connectivity notes

Worth recording, because diagnosing it was part of the work:

- `listener.ora` and `tnsnames.ora` referenced a stale hostname after the machine was renamed, so the listener service started and immediately failed to bind (`TNS-12545`). Repointed both to `localhost`.
- With the listener down at instance startup, the `XE` service never dynamically registered, giving `ORA-12514` on every TCP connect despite a running listener. Fixed with `ALTER SYSTEM SET LOCAL_LISTENER` + `ALTER SYSTEM REGISTER`.
- The ODBC driver must match Power BI's bit-depth — a 32-bit driver is invisible to 64-bit Power BI.

## Stack

Oracle Database 11g XE · PL/SQL · SQL\*Loader · ODBC · Power BI Desktop · DAX · SQLite · Python

## Known limitations

- `p_run_full_load` is a full refresh (`DELETE` + reload) — no incremental load, no restart-from-failure
- Dimensions are overwritten; no slowly-changing-dimension history
- 9,994 rows is small; partitioning and parallel DML are untested at this volume
