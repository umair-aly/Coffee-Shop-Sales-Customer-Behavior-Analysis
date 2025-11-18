-- 1) top-selling product categories and items across 

CREATE OR REPLACE VIEW top_selling_products_view AS
SELECT
  p.product_category,
  p.product_type,
  p.product,
  SUM(sr.line_item_amount) AS total_revenue,
  SUM(sr.quantity) AS total_units_sold
FROM sales_reciepts sr
JOIN product p 
ON sr.product_id = p.product_id
GROUP BY p.product_category, p.product_type, p.product
ORDER BY total_revenue DESC
LIMIT 50; 

-- 2) Which outlets and staff drive highest revenue

CREATE OR REPLACE VIEW Outlet_performance  AS
SELECT
  so.sales_outlet_id,
  so.store_city,
  COUNT(DISTINCT sr.transaction_id) AS num_transactions,
  ROUND(SUM(sr.line_item_amount),0) AS total_revenue,
  SUM(sr.quantity) AS total_units_sold,
  ROUND(SUM(sr.line_item_amount) / COUNT(DISTINCT sr.transaction_id),2) AS avg_transaction_value
FROM sales_reciepts sr
JOIN sales_outlet so 
ON sr.sales_outlet_id = so.sales_outlet_id
GROUP BY so.sales_outlet_id, so.store_city
ORDER BY total_revenue DESC;

-- Staff performance

CREATE OR REPLACE VIEW staff_performance  AS
SELECT
  s.staff_id,
  CONCAT(s.first_name, ' ', s.last_name) AS staff_name,
  s.position,
  s.location,
  COUNT(DISTINCT sr.transaction_id) AS num_transactions,
  ROUND(SUM(sr.line_item_amount),0) AS total_revenue,
  ROUND(SUM(sr.line_item_amount) / COUNT(DISTINCT sr.transaction_id),2) AS avg_transaction_value
FROM sales_reciepts sr
JOIN staff s 
ON sr.staff_id = s.staff_id
GROUP BY s.staff_id, s.first_name, s.last_name, s.position, s.location
ORDER BY total_revenue DESC;

-- 3) Seasonal & temporal trends

CREATE OR REPLACE VIEW Revenue_by_weekday_and_hour AS
SELECT 
    d.transaction_date,
    HOUR(STR_TO_DATE(sr.transaction_time, '%H:%i:%s')) AS hour_of_day,
    COUNT(DISTINCT sr.transaction_id) AS num_transactions,
    ROUND(SUM(sr.line_item_amount),0) AS Revenue
FROM sales_reciepts sr
JOIN dates d 
    ON sr.transaction_date = d.transaction_date   
GROUP BY d.transaction_date, hour_of_day          
ORDER BY d.transaction_date, hour_of_day;

-- 4) Customer segments (by generation, gender, loyalty) and revenue

CREATE OR REPLACE VIEW generation_gender_loyalty AS
SELECT
	g.generation,
    c.gender,
    COUNT(DISTINCT CASE WHEN c.loyalty_card_number IS NOT NULL THEN c.customer_id END) AS loyalty_count,
    COUNT(DISTINCT sr.customer_id) AS unique_customers,
    ROUND(SUM(sr.line_item_amount),0) AS total_revenue,
    ROUND(SUM(sr.line_item_amount) / COUNT(DISTINCT sr.customer_id),2) AS avg_spend_per_customer
FROM sales_reciepts sr
JOIN customer c 
    ON sr.customer_id = c.customer_id
LEFT JOIN generations g 
    ON c.birth_year = g.birth_year
GROUP BY g.generation, c.gender
ORDER BY total_revenue DESC;


-- 5) Retention vs new customer acquisition (per month)

CREATE OR REPLACE VIEW Retention_and_new_customer_acquisition AS
SELECT
  sr.transaction_date,
  COUNT(DISTINCT sr.customer_id) AS unique_customers,
  COUNT(DISTINCT CASE WHEN sr.transaction_date = fp.first_purchase_date THEN sr.customer_id END) AS new_customers,
  COUNT(DISTINCT CASE WHEN sr.transaction_date > fp.first_purchase_date THEN sr.customer_id END) AS returning_customers,
  ROUND(
    COUNT(DISTINCT CASE WHEN sr.transaction_date = fp.first_purchase_date THEN sr.customer_id END)
      /COUNT(DISTINCT sr.customer_id)* 100,2
  ) AS pct_new_customers
FROM sales_reciepts sr
JOIN (
  SELECT customer_id, MIN(transaction_date) AS first_purchase_date
  FROM sales_reciepts
  GROUP BY customer_id
) fp 
ON sr.customer_id = fp.customer_id
GROUP BY sr.transaction_date
ORDER BY sr.transaction_date;

-- 6) Average Order Value


CREATE OR REPLACE VIEW Average_Order_Value AS
SELECT
  transaction_date,
  COUNT(DISTINCT transaction_id) AS num_transactions,
  ROUND(SUM(line_item_amount),0) AS total_revenue,
  ROUND(SUM(line_item_amount) / COUNT(DISTINCT transaction_id),2) AS AOV
FROM sales_reciepts
GROUP BY transaction_date;


-- 7) Inventory waste effect

CREATE OR REPLACE VIEW Inventory_waste_effect AS
SELECT
  pi.sales_outlet_id,
  p.product_id,
  p.product,
  SUM(pi.quantity_sold) AS total_sold,
  SUM(pi.waste) AS total_waste_units,
  ROUND( (SUM(pi.waste) / NULLIF(SUM(pi.quantity_sold + pi.waste),0)) * 100, 2 ) AS pct_waste_estimated,
  MAX(p.current_wholesale_price) AS current_wholesale_price,
  ROUND(SUM(pi.waste) * MAX(p.current_wholesale_price), 2) AS est_cost_of_waste
FROM pastry_inventory pi
JOIN product p 
  ON pi.product_id = p.product_id
GROUP BY pi.sales_outlet_id, p.product_id, p.product
ORDER BY est_cost_of_waste DESC
LIMIT 50;

-- 8) Sales target achievement (daily) by outlet

CREATE OR REPLACE VIEW Sales_Targets  AS
SELECT 
st.sales_outlet_id,
st.`year_month`,
st.total_goal,
ROUND(SUM(ss.line_item_amount),0) AS Actual_Revenue,
CASE WHEN ss.line_item_amount <= st.total_goal THEN 'Above Target' ELSE 'Below Target' END  AS performance_status
FROM sales_target AS st
LEFT JOIN sales_reciepts as ss
USING(sales_outlet_id)
GROUP BY st.`year_month`,st.sales_outlet_id,st.total_goal,performance_status;


-- 9) Promotion effectiveness

CREATE OR REPLACE VIEW Promotion_effectiveness  AS
SELECT
  CASE WHEN sr.promo_item_yn = 'Y' OR p.promo_yn = 'Y' THEN 'Promo' ELSE 'Non-promo' END AS promo_flag,
  COUNT(DISTINCT sr.transaction_id) AS num_transactions,
  SUM(sr.line_item_amount) AS total_revenue,
  SUM(sr.quantity) AS total_units_sold,
  ROUND(SUM(sr.line_item_amount) / NULLIF(COUNT(DISTINCT sr.transaction_id),0),2) AS avg_transaction_value
FROM sales_reciepts sr
JOIN product
 p ON sr.product_id = p.product_id
GROUP BY promo_flag
ORDER BY total_revenue DESC;


-- 10) Coffee Beans — product type performance (volume & revenue growth)

CREATE OR REPLACE VIEW Coffee_Volume_and_Growth AS
WITH bean_sales AS (
  SELECT
    p.product_category,
    p.product_type,
    p.product,
    DATE_FORMAT(STR_TO_DATE(sr.transaction_date, '%c/%e/%Y'), '%m-%d') AS day_month,
    ROUND(SUM(sr.line_item_amount),0) AS revenue,
    ROUND(SUM(sr.quantity),0) AS units_sold
  FROM sales_reciepts sr
  JOIN product p 
    ON sr.product_id = p.product_id
  WHERE p.product_category = 'Coffee beans'
  GROUP BY
    p.product_category,
    p.product_type,
    p.product,
    DATE_FORMAT(STR_TO_DATE(sr.transaction_date, '%c/%e/%Y'), '%m-%d')
)

SELECT
 
  product_category,
  product_type,
  product,
  day_month,
  revenue,
  units_sold,
  LAG(revenue) OVER (PARTITION BY product_type ORDER BY day_month) AS prev_day_revenue,
  ROUND(
      (revenue - LAG(revenue) OVER (PARTITION BY product_type ORDER BY day_month))
      / LAG(revenue) OVER (PARTITION BY product_type ORDER BY day_month)* 100
  , 2) AS mom_growth_pct
FROM bean_sales
ORDER BY product_type, day_month;



-- 12) Coffee Beans — which individual products have highest repeat purchase / loyalty

CREATE OR REPLACE VIEW Coffee_repeat_buyers AS
WITH purchases AS (
  SELECT
    sr.customer_id,
    sr.product_id,
    COUNT(DISTINCT sr.transaction_id) AS purchases_by_customer_product
  FROM sales_reciepts sr
  JOIN product p ON sr.product_id = p.product_id
  WHERE p.product_category = 'Coffee beans'
  GROUP BY sr.customer_id, sr.product_id
)
SELECT
  p.product_id,
  p.product,
  COUNT(DISTINCT pr.customer_id) AS num_customers_who_bought,
  SUM(CASE WHEN pr.purchases_by_customer_product > 1 THEN 1 ELSE 0 END) AS num_repeat_customers,
  ROUND(SUM(CASE WHEN pr.purchases_by_customer_product > 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT pr.customer_id),0) * 100,2) AS repeat_rate_pct
FROM purchases pr
JOIN product p ON pr.product_id = p.product_id
GROUP BY p.product_id, p.product
ORDER BY repeat_rate_pct DESC, num_customers_who_bought DESC;



-- 13) LTV & RFM for Coffee Beans customers

CREATE OR REPLACE VIEW RFM AS
SELECT
  c.customer_id,
  c.customer_since,

   DATEDIFF(
   CURRENT_DATE,
   MIN(STR_TO_DATE(sr.transaction_date, '%c/%e/%Y'))
)  AS recency_days,

  COUNT(DISTINCT sr.transaction_id) AS frequency, 
  SUM(sr.line_item_amount) AS monetary,

  CASE 
      WHEN cb.customer_id IS NOT NULL THEN 'CoffeeBeansBuyer'
      ELSE 'NonCoffeeBeansBuyer'
  END AS buyer_type

FROM sales_reciepts sr
JOIN customer c 
  ON sr.customer_id = c.customer_id

LEFT JOIN (
   SELECT DISTINCT sr2.customer_id
   FROM sales_reciepts sr2
   JOIN product p2 ON sr2.product_id = p2.product_id
   WHERE p2.product_category = 'Coffee beans'
) cb
  ON sr.customer_id = cb.customer_id

GROUP BY c.customer_id, c.customer_since, cb.customer_id;


-- LTV
CREATE OR REPLACE VIEW LTV AS
WITH customer_sales AS (
  SELECT
    sr.customer_id,
    COUNT(DISTINCT sr.transaction_id) AS frequency,
    SUM(sr.line_item_amount) AS monetary
  FROM sales_reciepts sr
  GROUP BY sr.customer_id
),
coffee_buyers AS (
  SELECT DISTINCT sr.customer_id
  FROM sales_reciepts sr
  JOIN product p ON sr.product_id = p.product_id
  WHERE p.product_category = 'Coffee beans'
)
SELECT
  CASE WHEN cb.customer_id IS NOT NULL THEN 'CoffeeBeansBuyer'
       ELSE 'NonCoffeeBuyer'
  END AS segment,
  COUNT(cs.customer_id) AS num_customers,
  ROUND(AVG(cs.monetary),2) AS avg_lifetime_revenue_per_customer,
  ROUND(AVG(cs.frequency),2) AS avg_total_purchases_per_customer
FROM customer_sales cs
LEFT JOIN coffee_buyers cb
  ON cs.customer_id = cb.customer_id
GROUP BY segment;


-- 14) Staff Efficiency (Sales per Transaction Count)

CREATE OR REPLACE VIEW Staff_efficiency AS
SELECT 
    s.staff_id,
    CONCAT(s.first_name, ' ', s.last_name) AS staff_name,
    COUNT(DISTINCT sr.transaction_id) AS total_transactions,
    ROUND(SUM(sr.quantity * sr.unit_price), 2) AS total_sales,
    ROUND(SUM(sr.quantity * sr.unit_price) / COUNT(DISTINCT sr.transaction_id), 2) AS sales_per_transaction
FROM sales_reciepts sr
JOIN staff s 
    ON sr.staff_id = s.staff_id
GROUP BY s.staff_id, s.first_name, s.last_name
ORDER BY sales_per_transaction DESC;




-- 15) Outlet vs Coffee Bean Category Sales

CREATE OR REPLACE VIEW Outlet_Sales_of_Beans AS
SELECT 
    so.store_city,
    so.sales_outlet_id,
    ROUND(SUM(sr.quantity * sr.unit_price), 2) AS total_sales
FROM sales_reciepts sr
JOIN product p ON sr.product_id = p.product_id
JOIN sales_outlet so ON sr.sales_outlet_id = so.sales_outlet_id
WHERE p.product_category = 'Coffee beans'
GROUP BY so.sales_outlet_id, so.store_city
ORDER BY total_sales DESC;


SELECT
  c.customer_id,
  c.customer_since,

  DATEDIFF(
     CURRENT_DATE,
     MAX(STR_TO_DATE(sr.transaction_date, '%c/%e/%Y'))
  ) AS recency_days,

  COUNT(DISTINCT sr.transaction_id) AS frequency, 
  SUM(sr.line_item_amount) AS monetary,

  CASE 
      WHEN cb.customer_id IS NOT NULL THEN 'CoffeeBeansBuyer'
      ELSE 'NonCoffeeBeansBuyer'
  END AS buyer_type

FROM sales_reciepts sr
JOIN customer c 
  ON sr.customer_id = c.customer_id

LEFT JOIN (
   SELECT DISTINCT sr2.customer_id
   FROM sales_reciepts sr2
   JOIN product p2 
     ON sr2.product_id = p2.product_id
   WHERE p2.product_category = 'Coffee beans'
) cb
  ON sr.customer_id = cb.customer_id

GROUP BY c.customer_id, c.customer_since;


-- 15)  Beans_generation_gender_loyalty

CREATE OR REPLACE VIEW Beans_generation_gender_loyalty AS
SELECT
	g.generation,
    c.gender,
    COUNT(DISTINCT CASE WHEN c.loyalty_card_number IS NOT NULL THEN c.customer_id END) AS loyalty_count,
    COUNT(DISTINCT sr.customer_id) AS unique_customers,
    ROUND(SUM(sr.line_item_amount),0) AS total_revenue,
    ROUND(SUM(sr.line_item_amount) / COUNT(DISTINCT sr.customer_id),2) AS avg_spend_per_customer
FROM sales_reciepts sr
JOIN customer c 
    ON sr.customer_id = c.customer_id
JOIN product
USING(Product_id) 
LEFT JOIN generations g 
    ON c.birth_year = g.birth_year
Where product_category = "Coffee beans"
GROUP BY g.generation, c.gender
ORDER BY total_revenue DESC;
