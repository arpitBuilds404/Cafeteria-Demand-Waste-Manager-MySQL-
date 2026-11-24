// Express API on MySQL. All queries use placeholders (?) -> SQL-injection safe.
const express = require("express");
const mysql = require("mysql2/promise");
const app = express();
app.use(express.json());
app.use(express.static("public"));

const pool = mysql.createPool({
  host: process.env.DB_HOST || "localhost",
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASS || "",
  database: "cafeteria",
  dateStrings: true,
  connectionLimit: 10,
});
const q = async (sql, p = []) => (await pool.query(sql, p))[0];
const wrap = (fn) => async (req, res) => {
  try { res.json(await fn(req)); }
  catch (e) { res.status(400).json({ error: e.sqlMessage || e.message }); }
};

app.get("/api/dishes", wrap(() => q("SELECT dish_id, dish_name FROM dish")));
app.get("/api/ingredients", wrap(() => q("SELECT ingredient_id, ingredient_name, unit, stock, reorder_level FROM ingredient")));
app.get("/api/suppliers", wrap(() => q("SELECT supplier_id, supplier_name FROM supplier")));

app.get("/api/dashboard", wrap(async () => ({
  kpi: await q("SELECT * FROM v_daily_kpi ORDER BY prep_date DESC LIMIT 14"),
  low: await q("SELECT * FROM v_low_stock"),
  today: await q(`SELECT d.dish_name, p.qty_prepared, IFNULL(c.qty_consumed,0) consumed, IFNULL(w.qty,0) wasted
    FROM food_preparation p JOIN dish d USING(dish_id) LEFT JOIN consumption c USING(prep_id) LEFT JOIN food_waste w USING(prep_id)
    WHERE p.prep_date = CURDATE()`),
})));

app.post("/api/prepare", wrap(({ body }) =>
  q("CALL sp_prepare_food(?,?,?)", [+body.dish, +body.qty, body.fail ? 1 : 0]).then(() => ({ ok: "Committed" }))));
app.post("/api/usage", wrap(({ body }) =>
  q("CALL sp_record_usage(?,?,?,?)", [+body.dish, +body.cons, +body.waste, String(body.reason)]).then(() => ({ ok: "Saved" }))));
app.post("/api/purchase", wrap(({ body }) =>
  q("INSERT INTO purchase(ingredient_id,supplier_id,qty) VALUES(?,?,?)", [+body.ingredient, +body.supplier, +body.qty]).then(() => ({ ok: "Stock updated by trigger" }))));

app.get("/api/analytics", wrap(async () => ({
  ranking: await q(`SELECT d.dish_name, ROUND(AVG(w.qty/p.qty_prepared*100),1) avg_waste_pct,
      RANK() OVER (ORDER BY AVG(w.qty/p.qty_prepared) DESC) waste_rank
    FROM food_preparation p JOIN dish d USING(dish_id) JOIN food_waste w USING(prep_id)
    WHERE p.prep_date < CURDATE() GROUP BY d.dish_id, d.dish_name`),
  weekly: await q(`WITH weekly AS (
      SELECT YEARWEEK(p.prep_date,1) wk, SUM(p.qty_prepared) prepared, SUM(c.qty_consumed) consumed, SUM(w.qty) wasted
      FROM food_preparation p JOIN consumption c USING(prep_id) JOIN food_waste w USING(prep_id) GROUP BY wk)
    SELECT wk, prepared, consumed, wasted, prepared-consumed AS over_prepared FROM weekly ORDER BY wk DESC`),
})));
app.get("/api/audit", wrap(() => q("SELECT logged_at, event, detail FROM audit_log ORDER BY audit_id DESC LIMIT 100")));

app.listen(3000, () => console.log("http://localhost:3000"));
