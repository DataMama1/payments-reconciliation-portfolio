CREATE TABLE sales_orders (
    order_id            VARCHAR(50),
    transaction_date    VARCHAR(50),
    customer_name       VARCHAR(150),
    payment_channel     VARCHAR(50),
    currency            VARCHAR(10),
    gross_amount        VARCHAR(50),
    order_status        VARCHAR(30)
);

CREATE TABLE gateway_payouts (
    settlement_id       VARCHAR(50),
    order_id            VARCHAR(50),
    settlement_date     VARCHAR(50),
    gateway_name        VARCHAR(50),
    gross_settled       VARCHAR(50),
    fee_deducted        VARCHAR(50),
    net_payout          VARCHAR(50),
    payout_status       VARCHAR(50),
    gateway_reference   VARCHAR(100)
);


WITH 

-- Cleaning the Sales Orders

Cleaned_Sales AS (
    SELECT
        TRIM(UPPER(order_id)) AS clean_order_id,
        transaction_date,
        customer_name,
        payment_channel,
        currency,
        -- Postgres regex to strip ₦, commas, spaces, etc., and cast to numeric
        REGEXP_REPLACE(gross_amount, '[^0-9.]', '', 'g')::NUMERIC(12, 2) AS sales_gross_amount,
        order_status
    FROM sales_orders
),

-- Cleaning Gateway Points 

Cleaned_Gateway AS (
    SELECT
        settlement_id,
        TRIM(UPPER(order_id)) AS clean_order_id,
        settlement_date,
        gateway_name,
        REGEXP_REPLACE(gross_settled, '[^0-9.]', '', 'g')::NUMERIC(12, 2) AS gateway_gross_settled,
        REGEXP_REPLACE(fee_deducted, '[^0-9.]', '', 'g')::NUMERIC(12, 2) AS actual_fee_deducted,
        REGEXP_REPLACE(net_payout, '[^0-9.]', '', 'g')::NUMERIC(12, 2) AS actual_net_payout,
        payout_status,
        gateway_reference,
        -- Window function to flag double charges
        COUNT(*) OVER (PARTITION BY TRIM(UPPER(order_id))) AS charge_occurrence_count
    FROM gateway_payouts
),

-- Reconciliation matching and Contract Rules

Reconciled_Base AS (
    SELECT
        COALESCE(s.clean_order_id, g.clean_order_id) AS transaction_reference,
        s.transaction_date,
        g.settlement_date,
        s.customer_name,
        s.payment_channel,
        s.sales_gross_amount,
        g.gateway_gross_settled,
        g.actual_fee_deducted,
        g.actual_net_payout,
        g.payout_status,
        g.settlement_id,
        g.charge_occurrence_count,
        
        -- Contract Rule: 1.5% + NGN 100, capped at NGN 2,000
        LEAST(
            ROUND(((s.sales_gross_amount * 0.015) + 100.0)::NUMERIC, 2),
            2000.00
        ) AS expected_gateway_fee

    FROM Cleaned_Sales s
    FULL OUTER JOIN Cleaned_Gateway g
        ON s.clean_order_id = g.clean_order_id
)

-- STEP 4: Audit Classification and Root Cause Exception

SELECT
    transaction_reference,
    transaction_date,
    settlement_date,
    customer_name,
    payment_channel,
    sales_gross_amount,
    gateway_gross_settled,
    expected_gateway_fee,
    actual_fee_deducted,
    
    -- Fee Variance: Positive means the merchant was overcharged!
    ROUND((COALESCE(actual_fee_deducted, 0) - COALESCE(expected_gateway_fee, 0))::NUMERIC, 2) AS fee_leakage,
    
    ROUND((sales_gross_amount - expected_gateway_fee)::NUMERIC, 2) AS expected_net_payout,
    actual_net_payout,
    
    -- Automated Exception Classification
    CASE
        WHEN charge_occurrence_count > 1 THEN 'Duplicate Gateway Charge (Double Debit)'
        WHEN gateway_gross_settled IS NULL THEN 'Pending Settlement (T+1 in transit)'
        WHEN sales_gross_amount IS NULL THEN 'Unmatched Gateway Adjustment / Credit'
        WHEN payout_status = 'Disputed / Chargeback' THEN 'Unannounced Chargeback / Dispute'
        WHEN sales_gross_amount != gateway_gross_settled THEN 'Gross Amount Mismatch'
        WHEN (actual_fee_deducted - expected_gateway_fee) > 0.50 THEN 'Fee Overcharge (Revenue Leakage)'
        ELSE 'Fully Reconciled & Matched'
    END AS reconciliation_status,

    -- Prescribed Action for Operations Desk
    CASE
        WHEN charge_occurrence_count > 1 THEN 'Initiate immediate customer refund for duplicate debit'
        WHEN gateway_gross_settled IS NULL THEN 'Monitor T+1 settlement cycle with Paystack'
        WHEN sales_gross_amount IS NULL THEN 'Investigate unlinked credit with accounting'
        WHEN payout_status = 'Disputed / Chargeback' THEN 'Escalate to merchant chargeback dispute desk'
        WHEN sales_gross_amount != gateway_gross_settled THEN 'Investigate discount/partial payment breakdown'
        WHEN (actual_fee_deducted - expected_gateway_fee) > 0.50 THEN 'File recovery ticket with Paystack to refund excess fees'
        ELSE 'No action required'
    END AS operational_resolution

FROM Reconciled_Base;
