# Cafeteria Demand & Waste Manager (Node + MySQL)

## Setup
1. Install Node 18+ and MySQL 8+.
2. Create DB and data:  `mysql -u root -p < schema.sql`
3. `npm install`
4. `DB_USER=root DB_PASS=yourpassword npm start`  (PowerShell: `$env:DB_PASS="yourpassword"; npm start`)
5. Open http://localhost:3000

## Where each syllabus topic lives
- Tables (14), FK/CHECK/UNIQUE, 290+ seeded rows: schema.sql
- Views: v_daily_kpi, v_low_stock | Function: fn_waste_pct | Indexes: idx_prep_date, idx_purchase_ing
- Triggers: trg_low_stock, trg_prep_audit, trg_purchase_stock
- Procedures: sp_prepare_food (START TRANSACTION, SAVEPOINT, ROLLBACK), sp_record_usage
- Window function + CTE: GET /api/analytics in server.js
- SQL-injection safety: every query uses ? placeholders
- RBAC: roles at the end of schema.sql

## Concurrency demo (two mysql sessions)
Session A:  `START TRANSACTION; SELECT stock FROM ingredient WHERE ingredient_id=1 FOR UPDATE;`
Session B:  `START TRANSACTION; UPDATE ingredient SET stock=stock-5 WHERE ingredient_id=1;`  -- waits (row lock)
Session A:  `UPDATE ingredient SET stock=stock-5 WHERE ingredient_id=1; COMMIT;`  -- B now continues, no lost update
Deadlock: A locks ingredient 1 then 2, B locks 2 then 1; InnoDB aborts one with error 1213.

## Failure demo
Prepare 5000 Burgers (insufficient stock) or set "Simulate failure": stock stays unchanged and audit_log shows ROLLBACK.
