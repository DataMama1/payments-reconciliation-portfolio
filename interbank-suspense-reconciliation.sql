CREATE TABLE core_banking_txns (
    transaction_id VARCHAR(30),
    account VARCHAR(30),
    channel VARCHAR(10),
    amount NUMERIC(15,2),
    timestamp TIMESTAMP,
    status VARCHAR(30),
    switch_reference VARCHAR(50)
);

CREATE TABLE switch_settlement_report (
    switch_reference VARCHAR(50),
    amount NUMERIC(15,2),
    response_code VARCHAR(10),
    settlement_date DATE
);

CREATE TABLE suspense_gl (
    suspense_id VARCHAR(30),
    switch_reference VARCHAR(50),
    amount NUMERIC(15,2),
    posting_date DATE,
    reversal_date TIMESTAMP
);

-- to confirm records imported
SELECT
    (SELECT COUNT(*)
     FROM core_banking_txns) AS core_records,

    (SELECT COUNT(*)
     FROM switch_settlement_report) AS switch_records,

    (SELECT COUNT(*)
     FROM suspense_gl) AS suspense_records;

-- understanding the data before reconcilling

SELECT
    status,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount
FROM core_banking_txns
GROUP BY status
ORDER BY transaction_count DESC;

-- investigating the transactions that happened through NIP, ATM, POS and web

SELECT
    channel,
    COUNT(*) AS total_transactions,
    SUM(amount) AS total_value
FROM core_banking_txns
GROUP BY channel
ORDER BY total_transactions DESC;

-- checking for missing values

SELECT
    COUNT(*) AS total_records,

    COUNT(*) FILTER (
        WHERE transaction_id IS NULL
    ) AS missing_transaction_id,

    COUNT(*) FILTER (
        WHERE switch_reference IS NULL
    ) AS missing_switch_reference,

    COUNT(*) FILTER (
        WHERE amount IS NULL
    ) AS missing_amount,

    COUNT(*) FILTER (
        WHERE timestamp IS NULL
    ) AS missing_timestamp

FROM core_banking_txns;

-- checking for duplicate ID transactions

SELECT
    transaction_id,
    COUNT(*) AS occurrence
FROM core_banking_txns
GROUP BY transaction_id
HAVING COUNT(*) > 1;

-- checking for duplicate switch references

SELECT
    switch_reference,
    COUNT(*) AS occurrence,
    SUM(amount) AS total_amount
FROM core_banking_txns
GROUP BY switch_reference
HAVING COUNT(*) > 1
ORDER BY occurrence DESC;

-- checking transaction status distribution
SELECT
    status,
    COUNT(*) AS transaction_count,
    ROUND(SUM(amount), 2) AS total_value
FROM core_banking_txns
GROUP BY status
ORDER BY transaction_count DESC;

-- checking switch response codes
SELECT
    response_code,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_value
FROM switch_settlement_report
GROUP BY response_code
ORDER BY transaction_count DESC;

-- checking how many suspense items remain unresolved and the amount currently outstanding

SELECT
    COUNT(*) AS total_suspense_items,

    COUNT(*) FILTER (
        WHERE reversal_date IS NULL
    ) AS unreversed_items,

    COUNT(*) FILTER (
        WHERE reversal_date IS NOT NULL
    ) AS reversed_items,

    SUM(amount) FILTER (
        WHERE reversal_date IS NULL
    ) AS outstanding_value

FROM suspense_gl;

-- comparing the core banking records against the switch settlement report
SELECT
    c.transaction_id,
    c.switch_reference,
    c.channel,

    c.amount AS core_amount,
    c.status AS core_status,

    s.amount AS switch_amount,
    s.response_code,

    CASE

        WHEN s.switch_reference IS NULL
            THEN 'Missing from Switch'

        WHEN c.amount <> s.amount
            THEN 'Amount Mismatch'

        WHEN s.response_code = '00'
             AND c.status = 'SUCCESSFUL'
            THEN 'Successfully Matched'

        WHEN s.response_code = '00'
             AND c.status = 'FAILED'
            THEN 'Successful at Switch - Core Failed'

        WHEN s.response_code IN ('05', '91')
             AND c.status = 'DEBITED'
            THEN 'Debit Without Value'

        WHEN s.response_code IN ('05', '91')
             AND c.status = 'FAILED'
            THEN 'Failed - No Customer Debit'

        WHEN s.response_code IN ('05', '91')
             AND c.status = 'SUCCESSFUL'
            THEN 'Core Success - Switch Failed'

        ELSE 'Unclassified - Investigate'

    END AS reconciliation_result

FROM core_banking_txns c

LEFT JOIN switch_settlement_report s
    ON c.switch_reference = s.switch_reference

ORDER BY c.transaction_id;

-- creating a reconcillation view

CREATE OR REPLACE VIEW reconciliation_analysis AS

WITH core_ranked AS (
    SELECT
        c.*,

        COUNT(*) OVER (
            PARTITION BY switch_reference
        ) AS reference_count,

        ROW_NUMBER() OVER (
            PARTITION BY switch_reference
            ORDER BY timestamp, transaction_id
        ) AS reference_rank

    FROM core_banking_txns c
)

SELECT
    c.transaction_id,
    c.switch_reference,
    c.account,
    c.channel,
    c.timestamp,

    c.amount AS core_amount,
    c.status AS core_status,

    s.amount AS switch_amount,
    s.response_code,
    s.settlement_date,

    c.reference_count,
    c.reference_rank,

    CASE

        WHEN c.transaction_id IS NULL
             AND s.response_code = '00'
            THEN 'Successful at Switch - Missing from Core'

        WHEN c.transaction_id IS NULL
            THEN 'Switch Transaction - Missing from Core'

        WHEN s.switch_reference IS NULL
            THEN 'Missing from Switch'

        WHEN c.reference_rank > 1
            THEN 'Potential Duplicate Core Debit'

        WHEN c.amount <> s.amount
            THEN 'Amount Mismatch'

        WHEN s.response_code = '00'
             AND c.status = 'SUCCESSFUL'
            THEN 'Successfully Matched'

        WHEN s.response_code = '00'
             AND c.status = 'DEBITED'
            THEN 'Debit with Successful Switch - Investigate'

        WHEN s.response_code = '00'
             AND c.status = 'FAILED'
            THEN 'Successful at Switch - Core Failed'

        WHEN s.response_code IN ('05', '91')
             AND c.status = 'DEBITED'
            THEN 'Debit Without Value'

        WHEN s.response_code IN ('05', '91')
             AND c.status = 'FAILED'
            THEN 'Failed - No Customer Debit'

        WHEN s.response_code IN ('05', '91')
             AND c.status = 'SUCCESSFUL'
            THEN 'Core Success - Switch Failed'

        ELSE 'Unclassified - Investigate'

    END AS reconciliation_result

FROM core_ranked c

FULL OUTER JOIN switch_settlement_report s
    ON c.switch_reference = s.switch_reference;

-- reconcillation summary
SELECT
    switch_reference,
    COUNT(*) AS occurrence
FROM switch_settlement_report
GROUP BY switch_reference
HAVING COUNT(*) > 1;

-- checking suspense records for duplicates
SELECT
    switch_reference,
    COUNT(*) AS record_count,
    SUM(amount) AS total_amount
FROM suspense_gl
GROUP BY switch_reference
HAVING COUNT(*) > 1;

-- checking whether suspense references exist in core banking and switch reports
SELECT
    g.suspense_id,
    g.switch_reference,
    g.amount,
    g.posting_date,
    g.reversal_date,

    CASE
        WHEN c.switch_reference IS NULL
            THEN 'Missing from Core Banking'

        WHEN s.switch_reference IS NULL
            THEN 'Missing from Switch'

        ELSE 'Found in Both Systems'
    END AS reconciliation_status

FROM suspense_gl g



LEFT JOIN (
    SELECT DISTINCT switch_reference
    FROM core_banking_txns
) c
    ON g.switch_reference = c.switch_reference

LEFT JOIN (
    SELECT DISTINCT switch_reference
    FROM switch_settlement_report
) s
    ON g.switch_reference = s.switch_reference;

-- calculate actual outstanding suspense value
SELECT
    COUNT(*) AS total_suspense_items,

    COUNT(*) FILTER (
        WHERE reversal_date IS NULL
    ) AS open_items,

    COUNT(*) FILTER (
        WHERE reversal_date IS NOT NULL
    ) AS reversed_items,

    SUM(amount) FILTER (
        WHERE reversal_date IS NULL
    ) AS outstanding_value,

    SUM(amount) AS total_suspense_value

FROM suspense_gl;

-- query for suspense aging
WITH suspense_aging AS (

    SELECT
        suspense_id,
        switch_reference,
        amount,
        posting_date,
        reversal_date,

        CURRENT_DATE - posting_date AS days_outstanding

    FROM suspense_gl

    WHERE reversal_date IS NULL
),

bucketed_suspense AS (

    SELECT
        *,
        CASE
            WHEN days_outstanding BETWEEN 0 AND 1
                THEN '0-1 Days'

            WHEN days_outstanding BETWEEN 2 AND 3
                THEN '2-3 Days'

            WHEN days_outstanding BETWEEN 4 AND 7
                THEN '4-7 Days'

            ELSE '8+ Days'
        END AS aging_bucket

    FROM suspense_aging
)

SELECT
    aging_bucket,
    COUNT(*) AS number_of_items,
    SUM(amount) AS total_outstanding_value

FROM bucketed_suspense

GROUP BY aging_bucket

ORDER BY
    CASE
        WHEN aging_bucket = '0-1 Days' THEN 1
        WHEN aging_bucket = '2-3 Days' THEN 2
        WHEN aging_bucket = '4-7 Days' THEN 3
        WHEN aging_bucket = '8+ Days' THEN 4
    END;

-- Identifying the oldest unresolved transactions

SELECT
    suspense_id,
    switch_reference,
    amount,
    posting_date,

    CURRENT_DATE - posting_date AS days_outstanding

FROM suspense_gl

WHERE reversal_date IS NULL

ORDER BY days_outstanding DESC

LIMIT 10;

-- investigating whether the customers eventually received their reversals


WITH parameters AS (

    -- Change this value to adjust the reversal window
    SELECT 48::NUMERIC AS reversal_window_hours

),

reversal_tracking AS (

    SELECT
        g.suspense_id,
        g.switch_reference,
        g.amount,
        g.posting_date,
        g.reversal_date,

        c.timestamp AS debit_timestamp,

        p.reversal_window_hours,

        CASE
            WHEN g.reversal_date IS NOT NULL
            THEN ROUND(
                (
                    EXTRACT(
                        EPOCH FROM
                        (g.reversal_date - c.timestamp)
                    ) / 3600
                )::NUMERIC, 2
            )
        END AS reversal_hours

    FROM suspense_gl g

    LEFT JOIN LATERAL (

        SELECT
            timestamp

        FROM core_banking_txns c

        WHERE c.switch_reference = g.switch_reference
          AND c.status = 'DEBITED'

        ORDER BY timestamp

        LIMIT 1

    ) c ON TRUE

    CROSS JOIN parameters p

)

SELECT
    suspense_id,
    switch_reference,
    amount,
    debit_timestamp,
    reversal_date,
    reversal_hours,
    reversal_window_hours,

    CASE

        WHEN debit_timestamp IS NULL
            THEN 'Missing Debit Timestamp'

        WHEN reversal_date IS NULL
             AND CURRENT_TIMESTAMP >
                 debit_timestamp +
                 reversal_window_hours * INTERVAL '1 hour'
            THEN 'Open - SLA Breached'

        WHEN reversal_date IS NULL
            THEN 'Open - Within SLA'

        WHEN reversal_hours > reversal_window_hours
            THEN 'Reversed Late - SLA Breach'

        WHEN reversal_hours < 0
            THEN 'Invalid Reversal Timestamp'

        ELSE 'Reversed Within SLA'

    END AS reversal_status

FROM reversal_tracking

ORDER BY reversal_hours DESC NULLS LAST;

-- -- checking the distinct status values in core banking
-- confirms whether REVERSED exists before relying on it in the reversal logic

SELECT DISTINCT status FROM core_banking_txns;
SELECT MIN(posting_date), MAX(posting_date) FROM suspense_gl;

-- creating a parameters table to store adjustable settings
-- reversal_window_hours: maximum hours allowed for a reversal (illustrative 24-hour internal threshold)
-- reporting_date: fixed "as of" date used instead of CURRENT_DATE so results stay consistent
-- aged_suspense_days: number of days after which an open suspense item is flagged as aged
-- ON CONFLICT updates the value if the parameter already exists, so the script can be re-run safely
-- to change a setting later, update the value here and re-run the views; no query needs editing

CREATE TABLE IF NOT EXISTS reconciliation_parameters (
    parameter_name  VARCHAR(100) PRIMARY KEY,
    parameter_value TEXT
);

INSERT INTO reconciliation_parameters VALUES
 ('reversal_window_hours', '24'),
 ('reporting_date', (SELECT MAX(posting_date)::text FROM suspense_gl)),
 ('aged_suspense_days', '7')
ON CONFLICT (parameter_name) DO UPDATE SET parameter_value = EXCLUDED.parameter_value;


CREATE OR REPLACE VIEW params AS
SELECT
  (SELECT parameter_value::numeric FROM reconciliation_parameters WHERE parameter_name='reversal_window_hours') AS reversal_window_hours,
  (SELECT parameter_value::date    FROM reconciliation_parameters WHERE parameter_name='reporting_date')        AS reporting_date,
  (SELECT parameter_value::int     FROM reconciliation_parameters WHERE parameter_name='aged_suspense_days')    AS aged_days;

-- creating a params view that reads the settings table
-- converts each value to its proper data type (number, date, integer)
-- returns a single row, so any query can CROSS JOIN it to use the parameters

CREATE OR REPLACE VIEW params AS
SELECT
  (SELECT parameter_value::numeric FROM reconciliation_parameters WHERE parameter_name='reversal_window_hours') AS reversal_window_hours,
  (SELECT parameter_value::date    FROM reconciliation_parameters WHERE parameter_name='reporting_date')        AS reporting_date,
  (SELECT parameter_value::int     FROM reconciliation_parameters WHERE parameter_name='aged_suspense_days')    AS aged_days;

  -- creating the reversal monitoring view
-- for each suspense item, finds the earliest core debit/reversal timestamp for the same switch reference
-- calculates the hours between that debit and the reversal date
-- compares the duration against reversal_window_hours from the params view
-- classifies each item as:
--   Missing Debit Timestamp: no matching core transaction found
--   Open - SLA Breached: no reversal yet and the window has already passed at the reporting date
--   Open - Within SLA: no reversal yet but still inside the window
--   Invalid Reversal Timestamp: reversal date is earlier than the debit time (data error)
--   Reversed Late - SLA Breach: reversed, but took longer than the window
--   Reversed Within SLA: reversed inside the window
-- LATERAL join picks only one debit row per suspense item to prevent duplicate rows and double counting
-- uses reporting_date instead of CURRENT_DATE so the simulated data is not artificially aged

CREATE OR REPLACE VIEW reversal_monitoring AS
SELECT
  g.suspense_id, g.switch_reference, g.amount, g.posting_date, g.reversal_date,
  c.timestamp AS debit_timestamp,
  p.reversal_window_hours,
  ROUND((EXTRACT(EPOCH FROM (g.reversal_date - c.timestamp))/3600)::numeric, 2) AS reversal_hours,
  CASE
    WHEN c.timestamp IS NULL THEN 'Missing Debit Timestamp'
    WHEN g.reversal_date IS NULL
         AND (p.reporting_date + 1)::timestamp > c.timestamp + p.reversal_window_hours * INTERVAL '1 hour'
         THEN 'Open - SLA Breached'
    WHEN g.reversal_date IS NULL THEN 'Open - Within SLA'
    WHEN g.reversal_date < c.timestamp THEN 'Invalid Reversal Timestamp'
    WHEN EXTRACT(EPOCH FROM (g.reversal_date - c.timestamp))/3600 > p.reversal_window_hours
         THEN 'Reversed Late - SLA Breach'
    ELSE 'Reversed Within SLA'
  END AS reversal_status
FROM suspense_gl g
CROSS JOIN params p
LEFT JOIN LATERAL (
    SELECT timestamp FROM core_banking_txns c
    WHERE c.switch_reference = g.switch_reference
      AND c.status IN ('DEBITED','REVERSED')
    ORDER BY timestamp LIMIT 1
) c ON TRUE;

-- summarizing reversal monitoring results
-- shows the number of items and total value in each reversal status
-- used for the SLA breach KPI on the dashboard
-- re-run after changing reversal_window_hours (24 to 48) to confirm the breach count changes

SELECT reversal_status, COUNT(*) items, SUM(amount) value
FROM reversal_monitoring GROUP BY 1 ORDER BY 2 DESC;

--testing parameters
UPDATE reconciliation_parameters SET parameter_value = '48' WHERE parameter_name = 'reversal_window_hours';

SELECT reversal_status, COUNT(*) items, SUM(amount) value
FROM reversal_monitoring GROUP BY 1 ORDER BY 2 DESC;

UPDATE reconciliation_parameters SET parameter_value = '24' WHERE parameter_name = 'reversal_window_hours';

-- creating a view of open suspense items only (reversal_date IS NULL), aged from posting date to the fixed reporting date
-- assigns each item to an aging bucket (0-1, 2-3, 4-7, 8+ days) so value can be grouped by age

CREATE OR REPLACE VIEW suspense_aging_open AS
SELECT g.suspense_id, g.switch_reference, g.amount, g.posting_date,
       p.reporting_date - g.posting_date AS days_outstanding,
       CASE
         WHEN p.reporting_date - g.posting_date <= 1 THEN '0-1 Days'
         WHEN p.reporting_date - g.posting_date <= 3 THEN '2-3 Days'
         WHEN p.reporting_date - g.posting_date <= 7 THEN '4-7 Days'
         ELSE '8+ Days'
       END AS aging_bucket
FROM suspense_gl g CROSS JOIN params p
WHERE g.reversal_date IS NULL;

-- reconciliation check: total must equal the open outstanding value from the suspense summary (₦10,854,000)
-- a mismatch means the view is dropping or double counting items

SELECT aging_bucket, COUNT(*) items, SUM(amount) value
FROM suspense_aging_open GROUP BY 1 ORDER BY 1;

SELECT SUM(amount) FROM suspense_aging_open;

-- inspecting repeated switch references in core banking
-- checks account, amount and time gap to confirm real duplicates vs. reference reuse
SELECT switch_reference,
       COUNT(*) AS n,
       COUNT(DISTINCT account) AS accounts,
       COUNT(DISTINCT amount) AS amounts,
       MIN(timestamp) AS first_ts,
       MAX(timestamp) AS last_ts,
       ROUND(EXTRACT(EPOCH FROM (MAX(timestamp) - MIN(timestamp)))/60, 1) AS minutes_apart
FROM core_banking_txns
GROUP BY switch_reference
HAVING COUNT(*) > 1
ORDER BY n DESC;

-- exception count and value by break type
SELECT break_type, COUNT(*) n, SUM(amount_at_risk) value
FROM exception_register GROUP BY 1 ORDER BY 1;

-- creating the exception register: one row per break across all six break types
-- each row carries the break type, reference, channel, amount at risk and recommended next action
CREATE OR REPLACE VIEW exception_register AS
WITH rev AS (
  SELECT switch_reference,
         COUNT(reversal_date) AS reversed_entries
  FROM suspense_gl GROUP BY switch_reference
),
ra AS (SELECT * FROM reconciliation_analysis)

-- Break 1: Debit without value, no reversal found
SELECT 'Break 1 - Debit without value' AS break_type, ra.switch_reference, ra.transaction_id,
       COALESCE(ra.channel,'UNKNOWN') AS channel, ra.response_code,
       ra.core_amount AS amount_at_risk,
       'Confirm failure at switch and reverse customer debit' AS next_action
FROM ra LEFT JOIN rev USING (switch_reference)
WHERE ra.reconciliation_result = 'Debit Without Value'
  AND COALESCE(rev.reversed_entries,0) = 0

UNION ALL
-- Break 2: Successful at switch, not posted in core
SELECT 'Break 2 - Missing core posting', switch_reference, transaction_id,
       COALESCE(channel,'UNKNOWN'), response_code, COALESCE(switch_amount, core_amount),
       'Investigate core posting gap; post or confirm with switch'
FROM ra
WHERE reconciliation_result IN ('Successful at Switch - Missing from Core','Successful at Switch - Core Failed')

UNION ALL
-- Break 3: Duplicate debit (same reference, repeated)
SELECT 'Break 3 - Duplicate debit', switch_reference, transaction_id,
       COALESCE(channel,'UNKNOWN'), response_code, core_amount,
       'Verify duplicate and initiate reversal of excess debit'
FROM ra WHERE reconciliation_result = 'Potential Duplicate Core Debit'

UNION ALL
-- Break 4: Reversal late or never (within SLA parameter)
SELECT 'Break 4 - Reversal SLA breach', m.switch_reference, NULL,
       COALESCE(c.channel,'UNKNOWN'), NULL, m.amount,
       CASE WHEN m.reversal_status = 'Open - SLA Breached'
            THEN 'Escalate: no reversal within window'
            ELSE 'Document late reversal; review root cause' END
FROM reversal_monitoring m
LEFT JOIN (SELECT DISTINCT ON (switch_reference) switch_reference, channel
           FROM core_banking_txns ORDER BY switch_reference, timestamp) c
       USING (switch_reference)
WHERE m.reversal_status IN ('Open - SLA Breached','Reversed Late - SLA Breach')

UNION ALL
-- Break 5: Amount mismatch
SELECT 'Break 5 - Amount mismatch', switch_reference, transaction_id,
       COALESCE(channel,'UNKNOWN'), response_code, ABS(core_amount - switch_amount),
       'Investigate amount difference between core and switch'
FROM ra WHERE reconciliation_result = 'Amount Mismatch'

UNION ALL
-- Break 6: Aged suspense
SELECT 'Break 6 - Aged suspense', a.switch_reference, NULL,
       COALESCE(c.channel,'UNKNOWN'), NULL, a.amount,
       'Escalate unresolved suspense item (' || a.days_outstanding || ' days)'
FROM suspense_aging_open a CROSS JOIN params p
LEFT JOIN (SELECT DISTINCT ON (switch_reference) switch_reference, channel
           FROM core_banking_txns ORDER BY switch_reference, timestamp) c
       USING (switch_reference)
WHERE a.days_outstanding > p.aged_days;

-- exception count and value by break type
SELECT break_type, COUNT(*) n, SUM(amount_at_risk) value
FROM exception_register GROUP BY 1 ORDER BY 1;

-- logic gap check: anything here means a case the reconciliation view could not classify
SELECT * FROM reconciliation_analysis WHERE reconciliation_result LIKE 'Unclassified%' LIMIT 20;

-- every reconciliation row should land in exactly one result
SELECT reconciliation_result, COUNT(*) FROM reconciliation_analysis GROUP BY 1 ORDER BY 2 DESC;

-- exceptions by channel and break type
-- shows which channels drive which breaks
SELECT channel, break_type, COUNT(*) n, SUM(amount_at_risk) value
FROM exception_register GROUP BY 1,2 ORDER BY 1,2;

-- response codes behind debit-without-value
-- shows which failure code (05 or 91) causes most unreversed debits
SELECT response_code, COUNT(*) n, SUM(amount_at_risk) value
FROM exception_register WHERE break_type LIKE 'Break 1%' GROUP BY 1;

-- match rate by channel (dashboard KPI)
-- percentage of transactions that reconciled cleanly in each channel
SELECT COALESCE(channel,'UNKNOWN') channel,
       COUNT(*) total,
       COUNT(*) FILTER (WHERE reconciliation_result = 'Successfully Matched') matched,
       ROUND(100.0 * COUNT(*) FILTER (WHERE reconciliation_result = 'Successfully Matched') / COUNT(*), 2) match_rate_pct
FROM reconciliation_analysis GROUP BY 1 ORDER BY 4;

-- SLA breaches by day of week (0 = Sunday, 6 = Saturday)
-- only counts true breaches: open past the window, or reversed late
SELECT EXTRACT(DOW FROM debit_timestamp) dow, COUNT(*) breaches
FROM reversal_monitoring
WHERE reversal_status IN ('Open - SLA Breached','Reversed Late - SLA Breach')
GROUP BY 1 ORDER BY 1;

-- unique references with at least one exception
-- the correct headline count, since one reference can appear under several breaks
SELECT COUNT(DISTINCT switch_reference) AS unique_references_with_exceptions
FROM exception_register;

-- one row per switch reference, keeping the most severe break
-- use this view for headline counts and value at risk; use exception_register for detail
CREATE OR REPLACE VIEW exception_register_unique AS
SELECT DISTINCT ON (switch_reference) *
FROM exception_register
ORDER BY switch_reference,
  CASE break_type
    WHEN 'Break 1 - Debit without value' THEN 1
    WHEN 'Break 3 - Duplicate debit'     THEN 2
    WHEN 'Break 2 - Missing core posting' THEN 3
    WHEN 'Break 5 - Amount mismatch'     THEN 4
    WHEN 'Break 4 - Reversal SLA breach' THEN 5
    WHEN 'Break 6 - Aged suspense'       THEN 6
  END;

-- check: count must equal 463 (unique references with at least one exception)
SELECT COUNT(*) AS unique_refs, SUM(amount_at_risk) AS total_value_at_risk
FROM exception_register_unique;

-- match rate by channel, saved as a view for the dashboard
CREATE OR REPLACE VIEW match_rate_by_channel AS
SELECT COALESCE(channel,'UNKNOWN') AS channel,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE reconciliation_result = 'Successfully Matched') AS matched,
       ROUND(100.0 * COUNT(*) FILTER (WHERE reconciliation_result = 'Successfully Matched') / COUNT(*), 2) AS match_rate_pct
FROM reconciliation_analysis GROUP BY 1;

-- reconciliation view: now takes the reference from the switch side when core has no record
CREATE OR REPLACE VIEW reconciliation_analysis AS
WITH core_ranked AS (
    SELECT c.*,
        COUNT(*) OVER (PARTITION BY switch_reference) AS reference_count,
        ROW_NUMBER() OVER (PARTITION BY switch_reference ORDER BY timestamp, transaction_id) AS reference_rank
    FROM core_banking_txns c
)
SELECT
    c.transaction_id,
    COALESCE(c.switch_reference, s.switch_reference) AS switch_reference,
    c.account, c.channel, c.timestamp,
    c.amount AS core_amount, c.status AS core_status,
    s.amount AS switch_amount, s.response_code, s.settlement_date,
    c.reference_count, c.reference_rank,
    CASE
        WHEN c.transaction_id IS NULL AND s.response_code = '00' THEN 'Successful at Switch - Missing from Core'
        WHEN c.transaction_id IS NULL THEN 'Switch Transaction - Missing from Core'
        WHEN s.switch_reference IS NULL THEN 'Missing from Switch'
        WHEN c.reference_rank > 1 THEN 'Potential Duplicate Core Debit'
        WHEN c.amount <> s.amount THEN 'Amount Mismatch'
        WHEN s.response_code = '00' AND c.status = 'SUCCESSFUL' THEN 'Successfully Matched'
        WHEN s.response_code = '00' AND c.status = 'DEBITED' THEN 'Debit with Successful Switch - Investigate'
        WHEN s.response_code = '00' AND c.status = 'FAILED' THEN 'Successful at Switch - Core Failed'
        WHEN s.response_code IN ('05','91') AND c.status = 'DEBITED' THEN 'Debit Without Value'
        WHEN s.response_code IN ('05','91') AND c.status = 'FAILED' THEN 'Failed - No Customer Debit'
        WHEN s.response_code IN ('05','91') AND c.status = 'SUCCESSFUL' THEN 'Core Success - Switch Failed'
        ELSE 'Unclassified - Investigate'
    END AS reconciliation_result
FROM core_ranked c
FULL OUTER JOIN switch_settlement_report s
    ON c.switch_reference = s.switch_reference;

-- the unique count should now equal the distinct count, expected 463
SELECT COUNT(*) AS unique_refs, SUM(amount_at_risk) AS total_value_at_risk
FROM exception_register_unique;

SELECT COUNT(DISTINCT switch_reference) FROM exception_register;

-- the match rate by channel should be unchanged
SELECT * FROM match_rate_by_channel ORDER BY 1;

SELECT * FROM exception_register_unique;
SELECT * FROM reversal_monitoring;
SELECT * FROM suspense_aging_open;
SELECT * FROM match_rate_by_channel;
SELECT * FROM params;
