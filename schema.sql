-- Cafeteria Demand & Waste Management (MySQL 8+)
-- Run: mysql -u root -p < schema.sql
DROP DATABASE IF EXISTS cafeteria;
CREATE DATABASE cafeteria;
USE cafeteria;

CREATE TABLE meal_plan(plan_id INT AUTO_INCREMENT PRIMARY KEY, plan_name VARCHAR(40) NOT NULL UNIQUE, meals_per_day TINYINT NOT NULL CHECK (meals_per_day BETWEEN 1 AND 4));
CREATE TABLE student(student_id INT AUTO_INCREMENT PRIMARY KEY, full_name VARCHAR(80) NOT NULL, plan_id INT NOT NULL, FOREIGN KEY(plan_id) REFERENCES meal_plan(plan_id));
CREATE TABLE supplier(supplier_id INT AUTO_INCREMENT PRIMARY KEY, supplier_name VARCHAR(80) NOT NULL UNIQUE, phone VARCHAR(15));
CREATE TABLE ingredient(ingredient_id INT AUTO_INCREMENT PRIMARY KEY, ingredient_name VARCHAR(60) NOT NULL UNIQUE, unit VARCHAR(5) NOT NULL,
  stock DECIMAL(10,2) NOT NULL CHECK (stock >= 0), reorder_level DECIMAL(10,2) NOT NULL);
CREATE TABLE dish(dish_id INT AUTO_INCREMENT PRIMARY KEY, dish_name VARCHAR(60) NOT NULL UNIQUE, typical_demand INT NOT NULL);
CREATE TABLE recipe(dish_id INT, ingredient_id INT, qty_per_portion DECIMAL(6,3) NOT NULL CHECK (qty_per_portion > 0),
  PRIMARY KEY(dish_id, ingredient_id), FOREIGN KEY(dish_id) REFERENCES dish(dish_id), FOREIGN KEY(ingredient_id) REFERENCES ingredient(ingredient_id));
CREATE TABLE menu(menu_id INT AUTO_INCREMENT PRIMARY KEY, menu_date DATE NOT NULL, meal_type ENUM('Breakfast','Lunch','Dinner') NOT NULL, UNIQUE(menu_date, meal_type));
CREATE TABLE menu_item(menu_id INT, dish_id INT, PRIMARY KEY(menu_id, dish_id), FOREIGN KEY(menu_id) REFERENCES menu(menu_id), FOREIGN KEY(dish_id) REFERENCES dish(dish_id));
CREATE TABLE meal_attendance(menu_id INT, student_id INT, PRIMARY KEY(menu_id, student_id), FOREIGN KEY(menu_id) REFERENCES menu(menu_id), FOREIGN KEY(student_id) REFERENCES student(student_id));
CREATE TABLE purchase(purchase_id INT AUTO_INCREMENT PRIMARY KEY, ingredient_id INT NOT NULL, supplier_id INT NOT NULL, qty DECIMAL(10,2) NOT NULL CHECK (qty > 0),
  purchased_at DATETIME DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY(ingredient_id) REFERENCES ingredient(ingredient_id), FOREIGN KEY(supplier_id) REFERENCES supplier(supplier_id));
CREATE TABLE food_preparation(prep_id INT AUTO_INCREMENT PRIMARY KEY, prep_date DATE NOT NULL, dish_id INT NOT NULL, qty_prepared INT NOT NULL CHECK (qty_prepared > 0),
  UNIQUE(prep_date, dish_id), FOREIGN KEY(dish_id) REFERENCES dish(dish_id));
CREATE TABLE consumption(prep_id INT PRIMARY KEY, qty_consumed INT NOT NULL CHECK (qty_consumed >= 0), FOREIGN KEY(prep_id) REFERENCES food_preparation(prep_id));
CREATE TABLE food_waste(prep_id INT PRIMARY KEY, qty INT NOT NULL CHECK (qty >= 0), reason VARCHAR(40) NOT NULL, FOREIGN KEY(prep_id) REFERENCES food_preparation(prep_id));
CREATE TABLE audit_log(audit_id INT AUTO_INCREMENT PRIMARY KEY, logged_at DATETIME DEFAULT CURRENT_TIMESTAMP, event VARCHAR(30), detail VARCHAR(200));

CREATE INDEX idx_prep_date ON food_preparation(prep_date);
CREATE INDEX idx_purchase_ing ON purchase(ingredient_id, purchased_at);

-- ---------- Seed data ----------
INSERT INTO meal_plan(plan_name,meals_per_day) VALUES('Basic',1),('Standard',2),('Premium',3);
INSERT INTO supplier(supplier_name,phone) VALUES('Green Valley Traders','9810000001'),('Metro Wholesale','9810000002'),('Farm Fresh Co-op','9810000003');
INSERT INTO ingredient(ingredient_name,unit,stock,reorder_level) VALUES('Rice','kg',60,25),('Lentils','kg',30,12),('Paneer','kg',14,8),('Potatoes','kg',40,15),
 ('Wheat flour','kg',35,15),('Cooking oil','l',18,8),('Mixed vegetables','kg',22,10),('Chicken','kg',16,8);
INSERT INTO dish(dish_name,typical_demand) VALUES('Burger',150),('Fried rice',130),('Paneer roll',90),('Aloo sabzi',110),('Chapati',200),('Veg biryani',100),('Chicken curry',70);
INSERT INTO recipe VALUES(1,5,.08),(1,4,.06),(1,6,.01),(2,1,.12),(2,7,.05),(2,6,.015),(3,3,.06),(3,5,.05),(3,6,.02),(4,4,.1),(4,6,.01),(5,5,.06),(6,1,.1),(6,7,.06),(6,6,.015),(7,8,.15),(7,6,.02);
INSERT INTO student(full_name,plan_id) SELECT CONCAT('Student ',n), 1+n%3 FROM (WITH RECURSIVE s AS (SELECT 1 n UNION ALL SELECT n+1 FROM s WHERE n<40) SELECT n FROM s) x;
INSERT INTO food_preparation(prep_date,dish_id,qty_prepared)
 WITH RECURSIVE d AS (SELECT 1 n UNION ALL SELECT n+1 FROM d WHERE n<14)
 SELECT CURDATE()-INTERVAL d.n DAY, ds.dish_id, ROUND(ds.typical_demand*(0.9+RAND()*0.3)) FROM d CROSS JOIN dish ds;
INSERT INTO food_waste(prep_id,qty,reason) SELECT prep_id, FLOOR(qty_prepared*(0.04+RAND()*0.14)), 'Over-preparation' FROM food_preparation;
INSERT INTO consumption(prep_id,qty_consumed) SELECT p.prep_id, p.qty_prepared-w.qty-FLOOR(RAND()*3) FROM food_preparation p JOIN food_waste w USING(prep_id);
INSERT INTO food_preparation(prep_date,dish_id,qty_prepared) VALUES(CURDATE(),1,150),(CURDATE(),2,130),(CURDATE(),5,200);

-- ---------- Views ----------
CREATE VIEW v_daily_kpi AS
SELECT p.prep_date, SUM(p.qty_prepared) prepared, SUM(IFNULL(c.qty_consumed,0)) consumed, SUM(IFNULL(w.qty,0)) wasted,
       ROUND(100*SUM(IFNULL(w.qty,0))/SUM(p.qty_prepared),1) waste_pct
FROM food_preparation p LEFT JOIN consumption c USING(prep_id) LEFT JOIN food_waste w USING(prep_id) GROUP BY p.prep_date;
CREATE VIEW v_low_stock AS SELECT ingredient_name, stock, reorder_level, unit FROM ingredient WHERE stock < reorder_level;

-- ---------- Function, triggers, procedures ----------
DELIMITER //
CREATE FUNCTION fn_waste_pct(d DATE) RETURNS DECIMAL(5,1) READS SQL DATA
BEGIN DECLARE r DECIMAL(5,1); SELECT waste_pct INTO r FROM v_daily_kpi WHERE prep_date=d; RETURN IFNULL(r,0); END//

CREATE TRIGGER trg_low_stock AFTER UPDATE ON ingredient FOR EACH ROW
BEGIN IF NEW.stock < NEW.reorder_level AND OLD.stock >= NEW.reorder_level THEN
  INSERT INTO audit_log(event,detail) VALUES('LOW_STOCK', CONCAT(NEW.ingredient_name,' fell to ',NEW.stock,NEW.unit)); END IF; END//
CREATE TRIGGER trg_prep_audit AFTER INSERT ON food_preparation FOR EACH ROW
BEGIN INSERT INTO audit_log(event,detail) VALUES('PREPARE', CONCAT('dish ',NEW.dish_id,' x ',NEW.qty_prepared)); END//
CREATE TRIGGER trg_purchase_stock AFTER INSERT ON purchase FOR EACH ROW
BEGIN UPDATE ingredient SET stock = stock + NEW.qty WHERE ingredient_id = NEW.ingredient_id;
  INSERT INTO audit_log(event,detail) VALUES('PURCHASE', CONCAT('ingredient ',NEW.ingredient_id,' +',NEW.qty)); END//

-- Preparation: reserve stock, SAVEPOINT, insert; any error rolls everything back
CREATE PROCEDURE sp_prepare_food(IN p_dish INT, IN p_qty INT, IN p_fail BOOL)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; INSERT INTO audit_log(event,detail) VALUES('ROLLBACK',CONCAT('prepare dish ',p_dish)); RESIGNAL; END;
  START TRANSACTION;
  IF EXISTS(SELECT 1 FROM recipe r JOIN ingredient i USING(ingredient_id) WHERE r.dish_id=p_dish AND i.stock < r.qty_per_portion*p_qty FOR UPDATE)
    THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient ingredient stock'; END IF;
  UPDATE ingredient i JOIN recipe r USING(ingredient_id) SET i.stock = i.stock - r.qty_per_portion*p_qty WHERE r.dish_id=p_dish;
  SAVEPOINT after_stock;
  IF p_fail THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Simulated failure after savepoint'; END IF;
  INSERT INTO food_preparation(prep_date,dish_id,qty_prepared) VALUES(CURDATE(),p_dish,p_qty)
    ON DUPLICATE KEY UPDATE qty_prepared = qty_prepared + p_qty;
  COMMIT;
END//

CREATE PROCEDURE sp_record_usage(IN p_dish INT, IN p_cons INT, IN p_waste INT, IN p_reason VARCHAR(40))
BEGIN
  DECLARE v_prep INT; DECLARE v_qty INT;
  SELECT prep_id, qty_prepared INTO v_prep, v_qty FROM food_preparation WHERE prep_date=CURDATE() AND dish_id=p_dish;
  IF v_prep IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Dish not prepared today'; END IF;
  IF p_cons + p_waste > v_qty THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='consumed + wasted exceeds prepared'; END IF;
  START TRANSACTION;
  INSERT INTO consumption VALUES(v_prep,p_cons) ON DUPLICATE KEY UPDATE qty_consumed=p_cons;
  INSERT INTO food_waste VALUES(v_prep,p_waste,p_reason) ON DUPLICATE KEY UPDATE qty=p_waste, reason=p_reason;
  COMMIT;
END//
DELIMITER ;

-- ---------- RBAC ----------
CREATE ROLE IF NOT EXISTS cafeteria_staff, procurement_staff, cafeteria_manager;
GRANT SELECT ON cafeteria.* TO cafeteria_staff, procurement_staff;
GRANT EXECUTE ON PROCEDURE cafeteria.sp_prepare_food TO cafeteria_staff;
GRANT EXECUTE ON PROCEDURE cafeteria.sp_record_usage TO cafeteria_staff;
GRANT INSERT ON cafeteria.purchase TO procurement_staff;
GRANT ALL ON cafeteria.* TO cafeteria_manager;
