-- МФТИ, ДЗ №1. Аналитические SQL-запросы по исходным CSV.
-- Откройте этот файл в DBeaver на PostgreSQL@localhost.
-- Для скриншотов выполняйте по одному SELECT (поставить курсор внутрь запроса -> Выполнить SQL-выражение).
-- Объекты находятся в схеме mipt_hw1; другие базы/схемы менять не нужно.

-- ШАГ 2. ПРОВЕРКИ ЦЕЛОСТНОСТИ И ДУБЛЕЙ
-- A. Количество строк и уникальных значений первичного ключа.
SELECT 'customers' AS table_name, COUNT(*) AS rows_total, COUNT(DISTINCT customer_id) AS unique_ids,
       COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_ids FROM mipt_hw1.customers
UNION ALL
SELECT 'products', COUNT(*), COUNT(DISTINCT product_id), COUNT(*) - COUNT(DISTINCT product_id) FROM mipt_hw1.products
UNION ALL
SELECT 'orders', COUNT(*), COUNT(DISTINCT order_id), COUNT(*) - COUNT(DISTINCT order_id) FROM mipt_hw1.orders
UNION ALL
SELECT 'order_items', COUNT(*), COUNT(DISTINCT order_item_id), COUNT(*) - COUNT(DISTINCT order_item_id) FROM mipt_hw1.order_items;

-- B. Убедиться, что каждая строка с FK ссылается на существующую запись.
SELECT
  (SELECT COUNT(*) FROM mipt_hw1.orders o LEFT JOIN mipt_hw1.customers c ON c.customer_id=o.customer_id WHERE c.customer_id IS NULL) AS orders_without_customers,
  (SELECT COUNT(*) FROM mipt_hw1.order_items oi LEFT JOIN mipt_hw1.orders o ON o.order_id=oi.order_id WHERE o.order_id IS NULL) AS items_without_orders,
  (SELECT COUNT(*) FROM mipt_hw1.order_items oi LEFT JOIN mipt_hw1.products p ON p.product_id=oi.product_id WHERE p.product_id IS NULL) AS items_without_products;

-- ЗАПРОС 1. Пять продуктов с самой высокой средней ценой продажи.
SELECT product_id,
       ROUND(AVG(item_list_price_at_sale), 2) AS average_sale_price
FROM mipt_hw1.order_items
GROUP BY product_id
ORDER BY average_sale_price DESC, product_id
LIMIT 5;

-- ЗАПРОС 2. Выручка по брендам (цена позиции на момент продажи * количество).
SELECT p.brand,
       ROUND(SUM(oi.item_list_price_at_sale * oi.quantity), 2) AS total_sales_amount
FROM mipt_hw1.order_items oi
JOIN mipt_hw1.products p ON p.product_id = oi.product_id
GROUP BY p.brand
ORDER BY total_sales_amount DESC;

-- ЗАПРОС 3. Количество заказов по году и месяцу.
SELECT EXTRACT(YEAR FROM order_date)::INTEGER AS order_year,
       EXTRACT(MONTH FROM order_date)::INTEGER AS order_month,
       COUNT(*) AS order_count
FROM mipt_hw1.orders
GROUP BY 1, 2
ORDER BY 1, 2;

-- ЗАПРОС 4. Самый дорогой по себестоимости товар каждой продуктовой линейки.
-- При равенстве себестоимости выбран продукт с меньшим ID.
WITH ranked_products AS (
    SELECT product_id, product_line, standard_cost,
           ROW_NUMBER() OVER (PARTITION BY product_line ORDER BY standard_cost DESC, product_id) AS rn
    FROM mipt_hw1.products
)
SELECT product_id, product_line, standard_cost
FROM ranked_products
WHERE rn = 1
ORDER BY product_line;

-- ЗАПРОС 5. Число заказов и сумма продаж по статусу заказа.
-- COUNT(DISTINCT) нужен потому, что один заказ может содержать несколько позиций.
SELECT o.order_status,
       COUNT(DISTINCT o.order_id) AS order_count,
       ROUND(COALESCE(SUM(oi.item_list_price_at_sale * oi.quantity),0), 2) AS total_sales_amount
FROM mipt_hw1.orders o
LEFT JOIN mipt_hw1.order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_status
ORDER BY o.order_status;

-- ЗАПРОС 6. Клиенты, у которых нет ни одного заказа.
SELECT c.customer_id, c.last_name, c.first_name
FROM mipt_hw1.customers c
LEFT JOIN mipt_hw1.orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL
ORDER BY c.customer_id;

-- ЗАПРОС 7. Клиенты с максимальной и минимальной оценкой имущества по каждому штату.
-- При равенстве значения берём одну строку с наименьшим customer_id.
WITH ranked_customers AS (
    SELECT state, property_valuation, first_name, last_name, customer_id,
           ROW_NUMBER() OVER (PARTITION BY state ORDER BY property_valuation DESC, customer_id) AS highest_rn,
           ROW_NUMBER() OVER (PARTITION BY state ORDER BY property_valuation ASC, customer_id) AS lowest_rn
    FROM mipt_hw1.customers
)
SELECT state,
       CASE WHEN highest_rn = 1 THEN 'highest' ELSE 'lowest' END AS valuation_type,
       property_valuation, last_name, first_name
FROM ranked_customers
WHERE highest_rn = 1 OR lowest_rn = 1
ORDER BY state, valuation_type;

-- ЗАПРОС 8. Клиенты, покупавшие товары только из одной продуктовой линейки.
-- COUNT(DISTINCT order_id) считает заказы, а не отдельные товары.
SELECT o.customer_id,
       MIN(p.product_line) AS product_line,
       COUNT(DISTINCT o.order_id) AS order_count
FROM mipt_hw1.orders o
JOIN mipt_hw1.order_items oi ON oi.order_id = o.order_id
JOIN mipt_hw1.products p ON p.product_id = oi.product_id
GROUP BY o.customer_id
HAVING COUNT(DISTINCT p.product_line) = 1
ORDER BY o.customer_id;

-- ЗАПРОС 9. Доля отменённых заказов в каждой категории товаров (product_class).
-- Считаем уникальные заказы внутри категории, т.к. один заказ содержит несколько позиций.
SELECT p.product_class,
       COUNT(DISTINCT oi.order_id) AS all_orders,
       COUNT(DISTINCT oi.order_id) FILTER (WHERE o.order_status = 'Cancelled') AS cancelled_orders,
       ROUND(100.0 * COUNT(DISTINCT oi.order_id) FILTER (WHERE o.order_status = 'Cancelled')
             / NULLIF(COUNT(DISTINCT oi.order_id),0), 2) AS cancelled_percent
FROM mipt_hw1.order_items oi
JOIN mipt_hw1.products p ON p.product_id = oi.product_id
JOIN mipt_hw1.orders o ON o.order_id = oi.order_id
GROUP BY p.product_class
ORDER BY p.product_class;

-- ЗАПРОС 10. Сегментация клиентов по количеству заказов (включая клиентов без заказов).
WITH customer_orders AS (
    SELECT c.customer_id, COUNT(o.order_id) AS order_count
    FROM mipt_hw1.customers c
    LEFT JOIN mipt_hw1.orders o ON o.customer_id = c.customer_id
    GROUP BY c.customer_id
), labeled AS (
    SELECT CASE
             WHEN order_count > 10 THEN 'High'
             WHEN order_count BETWEEN 5 AND 10 THEN 'Medium'
             ELSE 'Low'
           END AS segment
    FROM customer_orders
)
SELECT segment, COUNT(*) AS customers_count
FROM labeled
GROUP BY segment
ORDER BY CASE segment WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;

-- ЗАПРОС 11. Наибольший разрыв между последовательными заказами клиента, в днях.
-- Доли дня сохраняются, потому что order_date имеет и дату, и время.
WITH ordered AS (
    SELECT customer_id, order_id, order_date,
           LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS previous_order_date
    FROM mipt_hw1.orders
), intervals AS (
    SELECT customer_id,
           EXTRACT(EPOCH FROM (order_date - previous_order_date)) / 86400.0 AS gap_days
    FROM ordered
    WHERE previous_order_date IS NOT NULL
)
SELECT c.first_name, c.last_name, c.job_title,
       ROUND(MAX(i.gap_days)::NUMERIC, 2) AS max_days_between_orders
FROM intervals i
JOIN mipt_hw1.customers c ON c.customer_id = i.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.job_title
ORDER BY max_days_between_orders DESC, c.customer_id;
