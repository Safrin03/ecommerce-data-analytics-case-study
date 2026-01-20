
-- 1. O2C & Communication Performance

--  1.1. WhatsApp O2C connect rate = (Clicked + Replied) / Delivered
SELECT 
    ROUND((SUM(CASE WHEN customer_action IN ('Clicked', 'Replied') THEN 1 ELSE 0 END) * 100.0 ) / 
		NULLIF(SUM(CASE WHEN delivery_status = 'Delivered' THEN 1 ELSE 0 END), 0), 2) AS whatsapp_o2c_connect_rate
FROM communication_logs
WHERE channel = 'WhatsApp'
AND template_type = 'O2C';


-- 1.2. City-wise Bottom 5 cities by WhatsApp O2C connect rate
SELECT 
    o.city,
    ROUND(
        (
            SUM(CASE WHEN c.customer_action IN ('Clicked', 'Replied') THEN 1 ELSE 0 END) * 100.0
        ) /
        NULLIF(SUM(CASE WHEN c.delivery_status = 'Delivered' THEN 1 ELSE 0 END), 0),
        2
    ) AS o2c_connect_rate
FROM orders o
JOIN communication_logs c ON o.order_id = c.order_id
WHERE c.channel = 'WhatsApp' AND c.template_type = 'O2C'
GROUP BY o.city
ORDER BY o2c_connect_rate ASC
LIMIT 5;

-- 2. Customer Purchase Behavior

-- 2.1. Repeat purchase rate by city (customer-level)
SELECT 
    city,
    ROUND( COUNT(DISTINCT CASE WHEN is_repeat_customer = 'True' THEN customer_id END) * 100.0 / 
    COUNT(DISTINCT customer_id), 2) AS repeat_purchase_rate_city
FROM orders
GROUP BY city
ORDER BY repeat_purchase_rate_city DESC;


-- 2.2. Repeat purchase rate by product_category (customer-level)
SELECT 
    product_category,
    ROUND(COUNT(DISTINCT CASE WHEN is_repeat_customer = 'True' THEN customer_id END) * 100.0 / 
    COUNT(DISTINCT customer_id), 2) AS repeat_purchase_rate_pc
FROM orders
GROUP BY product_category
ORDER BY repeat_purchase_rate_pc DESC;


-- 2.3. Cohort table: first purchase month x repeat purchase month (customer counts)

WITH first_purchases AS (
    -- Step 1: Find the first purchase date for every customer
    SELECT 
        customer_id, 
        MIN(DATE_FORMAT(order_date, '%Y-%m-01')) AS Raw_Month
    FROM orders
    GROUP BY customer_id
),
retention_data AS (
    -- Step 2: Calculate the difference in months between first and subsequent orders
    SELECT 
        o.customer_id,
        f.Raw_Month,
        TIMESTAMPDIFF(MONTH, f.Raw_Month, DATE_FORMAT(o.order_date, '%Y-%m-01')) AS month_index
    FROM orders o
    JOIN first_purchases f ON o.customer_id = f.customer_id
)
-- Step 3: Pivot the data into columns and format the month name
SELECT 
    DATE_FORMAT(Raw_Month, '%b %Y') AS First_Purchase_Month,
    COUNT(DISTINCT CASE WHEN month_index = 0 THEN customer_id END) AS Month_0,
    COUNT(DISTINCT CASE WHEN month_index = 1 THEN customer_id END) AS Month_1,
    COUNT(DISTINCT CASE WHEN month_index = 2 THEN customer_id END) AS Month_2,
    COUNT(DISTINCT CASE WHEN month_index = 3 THEN customer_id END) AS Month_3,
    COUNT(DISTINCT CASE WHEN month_index = 4 THEN customer_id END) AS Month_4,
    COUNT(DISTINCT CASE WHEN month_index = 5 THEN customer_id END) AS Month_5,
    COUNT(DISTINCT CASE WHEN month_index = 6 THEN customer_id END) AS Month_6,
    COUNT(DISTINCT CASE WHEN month_index = 7 THEN customer_id END) AS Month_7,
    COUNT(DISTINCT CASE WHEN month_index = 8 THEN customer_id END) AS Month_8,
    COUNT(DISTINCT CASE WHEN month_index = 9 THEN customer_id END) AS Month_9,
    COUNT(DISTINCT CASE WHEN month_index = 10 THEN customer_id END) AS Month_10,
    COUNT(DISTINCT CASE WHEN month_index = 11 THEN customer_id END) AS Month_11
FROM retention_data
GROUP BY Raw_Month
ORDER BY Raw_Month;

-- 3. Delivery & Supply Chain

--  3.1. Delivery gap in days for each order
SELECT 
    order_id,
    city,
    promised_delivery_date,
    actual_delivery_date,
    DATEDIFF(actual_delivery_date, promised_delivery_date) AS delivery_gap_days,
    CASE 
        WHEN DATEDIFF(actual_delivery_date, promised_delivery_date) > 0 THEN 'Late'
        WHEN DATEDIFF(actual_delivery_date, promised_delivery_date) < 0 THEN 'Early'
        ELSE 'On time'
    END AS delivery_status
FROM orders
WHERE actual_delivery_date IS NOT NULL 
  AND promised_delivery_date IS NOT NULL
ORDER BY order_id ASC;
  
-- 3.2. Orders delayed due to courier delay
SELECT 
    o.order_id, 
    o.city, 
    o.shipment_partner,
    o.promised_delivery_date, 
    o.actual_delivery_date, 
    DATEDIFF(o.actual_delivery_date, o.promised_delivery_date) AS delay_days,
    s.courier_delay_flag
FROM orders o
JOIN supply_chain s ON o.order_id = s.order_id
WHERE s.courier_delay_flag = 'True'
  AND o.actual_delivery_date > o.promised_delivery_date
ORDER BY order_id ASC;

-- 3.3 Rank courier partners by average shipment TAT
SELECT 
    o.shipment_partner,
    ROUND(AVG(s.shipment_tat_hours), 2) AS avg_tat_hours,
    RANK() OVER (ORDER BY AVG(s.shipment_tat_hours) ASC) AS courier_rank
FROM orders o
JOIN supply_chain s ON o.order_id = s.order_id
GROUP BY o.shipment_partner;

-- 3.4. Identify if delivery delay based on same-city vs different-city warehouse fulfillment
SELECT
    CASE
        WHEN o.city = 'Bangalore' AND sc.warehouse = 'BLR' THEN 'Same City'
        WHEN o.city = 'Mumbai' AND sc.warehouse = 'BOM' THEN 'Same City'
        WHEN o.city = 'Hyderabad' AND sc.warehouse = 'HYD' THEN 'Same City'
        WHEN o.city = 'Kolkata' AND sc.warehouse = 'DEL' THEN 'Different City'
        WHEN o.city = 'Delhi' AND sc.warehouse IN ('DEL', 'GGN') THEN 'Same Metro'
        ELSE 'Different City'
    END AS fulfillment_type,
    COUNT(*) AS total_orders,
    ROUND(
        AVG(DATEDIFF(o.actual_delivery_date, o.promised_delivery_date)),2) AS avg_delivery_delay_days,
    ROUND(
        COUNT(CASE WHEN o.actual_delivery_date > o.promised_delivery_date THEN 1 END) * 100.0 / COUNT(*),2) AS delayed_order_pct
FROM orders o
JOIN supply_chain sc 
    ON o.order_id = sc.order_id
WHERE o.actual_delivery_date IS NOT NULL
  AND o.promised_delivery_date IS NOT NULL
GROUP BY fulfillment_type
ORDER BY avg_delivery_delay_days DESC;


-- 4. Communication channel performance metrics
SELECT 
    channel,
    COUNT(*) AS total_messages,
    ROUND(COUNT(CASE WHEN delivery_status IN ('Delivered', 'Read') THEN 1 END) * 100.0 / COUNT(*), 2) AS delivery_rate,
	ROUND(COUNT(CASE WHEN delivery_status = 'Read' THEN 1 END) * 100.0 / 
	  NULLIF(COUNT(CASE WHEN delivery_status IN ('Delivered', 'Read') THEN 1 END), 0), 2) AS read_rate,
	ROUND(COUNT(CASE WHEN customer_action = 'Clicked' THEN 1 END) * 100.0 / 
	  NULLIF(COUNT(CASE WHEN delivery_status IN ('Delivered', 'Read') THEN 1 END), 0), 2) AS ctr,
	ROUND(COUNT(CASE WHEN customer_action = 'Replied' THEN 1 END) * 100.0 / 
	  NULLIF(COUNT(CASE WHEN delivery_status IN ('Delivered', 'Read') THEN 1 END), 0), 2) AS reply_rate
FROM communication_logs
GROUP BY channel
ORDER BY channel;


-- 5. Support ticket analysis by issue category 
SELECT 
    issue_category,
    COUNT(*) AS total_tickets,
    -- Calculate the difference between creation and resolution timestamps
    ROUND(AVG(CASE WHEN resolution_status = 'Resolved'THEN TIMESTAMPDIFF(HOUR, created_at, resolved_at) END), 2) AS avg_resolution_time_hrs,
    -- (Number of escalated tickets / Total tickets in that category) * 100
    ROUND(COUNT(CASE WHEN resolution_status = 'Escalated' THEN 1 END) * 100.0 / COUNT(*), 2) AS escalation_rate,
    ROUND(AVG(csat_score), 2) AS avg_csat_score
FROM support_tickets
GROUP BY issue_category
ORDER BY total_tickets DESC;

-- 6. Vet Transfer Analysis

-- 6.1. % of delivered orders with vet consultation within 72 hours post delivery
SELECT 
	COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT v.order_id) AS orders_with_vet_call,
    ROUND(COUNT(DISTINCT v.order_id) * 100.0 / COUNT(DISTINCT o.order_id), 2) AS vet_consult_pct_72h
FROM orders o
LEFT JOIN vet_calls v ON o.order_id = v.order_id 
    AND v.call_start_time >= o.actual_delivery_date 
    AND v.call_start_time <= DATE_ADD(o.actual_delivery_date, INTERVAL 72 HOUR)
WHERE o.order_status = 'Delivered' 
  AND o.actual_delivery_date IS NOT NULL;

-- 6.2. Average duration of successful vet transfers (in minutes)
SELECT 
    ROUND(AVG(call_duration_secs) / 60.0, 2) AS avg_successful_duration_mins
FROM vet_calls
WHERE vet_transfer_success = 'True';

