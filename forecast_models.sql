
USE DATABASE <YOUR_DATABASE>;
USE SCHEMA <YOUR_SCHEMA>;


-- ============================================================
-- STEP 1: INPUT VIEWS
-- ============================================================
-- These views expose the time-series data that ML.FORECAST
-- requires. Each view produces two columns:
--   ds  -- the date (timestamp for the model)
--   y   -- the numeric value being predicted
--
-- Multi-series views add a third column:
--   series_id -- groups the series (task_id or dept_id)
--
-- The views filter to business days only. Weekends and
-- holidays naturally produce no rows in TASK_LOG, so the
-- model handles sparse dates automatically.
-- ============================================================


-- View 1: Daily bike output
-- One row per business day. y = number of bikes that reached
-- T14 (Packaging and Labeling) -- the final assembly step.
-- A bike reaching T14 is counted as fully completed.
CREATE OR REPLACE VIEW V_DAILY_BIKE_OUTPUT AS
SELECT
    task_date                        AS ds,
    COUNT(DISTINCT bike_unit_id)     AS y
FROM TASK_LOG
WHERE task_id = 'T14'
GROUP BY task_date
ORDER BY task_date;


-- View 2: Weekly on-time rate
-- One row per week. y = percentage of tasks completed on or
-- before their scheduled_end_time across all task types.
-- Aggregated weekly to smooth day-to-day noise.
CREATE OR REPLACE VIEW V_WEEKLY_ONTIME_RATE AS
SELECT
    DATE_TRUNC('WEEK', task_date)                                        AS ds,
    ROUND(
        SUM(CASE WHEN actual_end_time <= scheduled_end_time THEN 1 ELSE 0 END)
        / COUNT(*) * 100
    , 2)                                                                 AS y
FROM TASK_LOG
GROUP BY DATE_TRUNC('WEEK', task_date)
ORDER BY ds;


-- View 3: Daily average task duration by task (multi-series)
-- One row per task_id per business day.
-- series_id = task_id (T1 through T14).
-- y = average duration in minutes for that task on that day.
-- The model produces a separate 30-day forecast line per task.
CREATE OR REPLACE VIEW V_TASK_DURATION_DAILY AS
SELECT
    task_date                                                            AS ds,
    task_id                                                              AS series_id,
    ROUND(
        AVG(TIMEDIFF(SECOND, start_time, actual_end_time)) / 60.0
    , 2)                                                                 AS y
FROM TASK_LOG
GROUP BY task_date, task_id
ORDER BY task_date, task_id;


-- View 4: Daily task throughput by department (multi-series)
-- One row per dept_id per business day.
-- series_id = dept_id (FRM, DRIV, WHL, FQC, PACK).
-- y = total tasks completed by that department on that day.
CREATE OR REPLACE VIEW V_DEPT_DAILY_THROUGHPUT AS
SELECT
    tl.task_date                                                         AS ds,
    d.dept_id                                                            AS series_id,
    COUNT(*)                                                             AS y
FROM TASK_LOG tl
JOIN EMPLOYEE e  ON tl.employee_id   = e.employee_id
JOIN DEPARTMENT d ON e.department_id = d.dept_id
GROUP BY tl.task_date, d.dept_id
ORDER BY tl.task_date, d.dept_id;


-- ============================================================
-- STEP 2: RESULTS STORAGE TABLES
-- ============================================================
-- Each forecast run stores its results here with a
-- run_timestamp so the agent always reads the latest run.
-- Previous runs are retained for auditability.
--
-- Columns returned by ML.FORECAST:
--   TS          -- forecasted date
--   FORECAST    -- point estimate
--   LOWER_BOUND -- 10th percentile (lower confidence bound)
--   UPPER_BOUND -- 90th percentile (upper confidence bound)
-- ============================================================


CREATE TABLE IF NOT EXISTS FORECAST_BIKE_OUTPUT (
    run_timestamp   TIMESTAMP_NTZ  NOT NULL,
    ts              DATE           NOT NULL,
    forecast        FLOAT          NOT NULL,
    lower_bound     FLOAT          NOT NULL,
    upper_bound     FLOAT          NOT NULL
);

CREATE TABLE IF NOT EXISTS FORECAST_ONTIME_RATE (
    run_timestamp   TIMESTAMP_NTZ  NOT NULL,
    ts              DATE           NOT NULL,
    forecast        FLOAT          NOT NULL,
    lower_bound     FLOAT          NOT NULL,
    upper_bound     FLOAT          NOT NULL
);

CREATE TABLE IF NOT EXISTS FORECAST_TASK_DURATION (
    run_timestamp   TIMESTAMP_NTZ  NOT NULL,
    series_id       VARCHAR(10)    NOT NULL,   -- task_id
    ts              DATE           NOT NULL,
    forecast        FLOAT          NOT NULL,
    lower_bound     FLOAT          NOT NULL,
    upper_bound     FLOAT          NOT NULL
);

CREATE TABLE IF NOT EXISTS FORECAST_DEPT_THROUGHPUT (
    run_timestamp   TIMESTAMP_NTZ  NOT NULL,
    series_id       VARCHAR(10)    NOT NULL,   -- dept_id
    ts              DATE           NOT NULL,
    forecast        FLOAT          NOT NULL,
    lower_bound     FLOAT          NOT NULL,
    upper_bound     FLOAT          NOT NULL
);


-- ============================================================
-- STEP 3: ML.FORECAST MODEL TRAINING
-- ============================================================
-- Run this section ONCE to train all four models.
-- Training reads the full historical dataset (2023).
-- Rerun whenever the underlying data changes significantly
-- (e.g., when a new year of data is loaded).
--
-- IMPORTANT: MODEL TRAINING REQUIRES THE SNOWFLAKE ML FEATURE
-- FLAG TO BE ENABLED ON YOUR ACCOUNT. CONTACT YOUR SNOWFLAKE
-- ADMIN IF YOU RECEIVE A FEATURE NOT ENABLED ERROR.
--
-- Prediction interval of 0.8 means the LOWER_BOUND and
-- UPPER_BOUND represent the 10th and 90th percentiles
-- (80% confidence interval).
-- ============================================================


-- Model 1: Daily bike output (single series)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST MODEL_BIKE_OUTPUT (
    INPUT_DATA          => SYSTEM$REFERENCE('VIEW', 'V_DAILY_BIKE_OUTPUT'),
    TIMESTAMP_COLNAME   => 'DS',
    TARGET_COLNAME      => 'Y'
);

-- Model 2: Weekly on-time rate (single series)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST MODEL_ONTIME_RATE (
    INPUT_DATA          => SYSTEM$REFERENCE('VIEW', 'V_WEEKLY_ONTIME_RATE'),
    TIMESTAMP_COLNAME   => 'DS',
    TARGET_COLNAME      => 'Y'
);

-- Model 3: Task duration by task (multi-series, one line per task_id)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST MODEL_TASK_DURATION (
    INPUT_DATA          => SYSTEM$REFERENCE('VIEW', 'V_TASK_DURATION_DAILY'),
    SERIES_COLNAME      => 'SERIES_ID',
    TIMESTAMP_COLNAME   => 'DS',
    TARGET_COLNAME      => 'Y'
);

-- Model 4: Department throughput (multi-series, one line per dept_id)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST MODEL_DEPT_THROUGHPUT (
    INPUT_DATA          => SYSTEM$REFERENCE('VIEW', 'V_DEPT_DAILY_THROUGHPUT'),
    SERIES_COLNAME      => 'SERIES_ID',
    TIMESTAMP_COLNAME   => 'DS',
    TARGET_COLNAME      => 'Y'
);


-- ============================================================
-- STEP 4: ON-DEMAND FORECAST PROCEDURES
-- ============================================================
-- Each procedure calls !FORECAST() on its pre-trained model,
-- writes the results into the corresponding storage table,
-- and returns the results as a result set.
--
-- All procedures accept an optional p_periods parameter
-- (default 30 days) so the user can override the horizon
-- at query time if needed.
-- ============================================================


-- =============================================
-- UPDATED STORED PROCEDURES (RESULT_SCAN PATTERN)
-- =============================================

-- Procedure 1: Bike Output Forecast
CREATE OR REPLACE PROCEDURE SP_FORECAST_BIKE_OUTPUT (p_periods INT DEFAULT 30)
RETURNS TABLE (
    ts              DATE,
    forecast        FLOAT,
    lower_bound     FLOAT,
    upper_bound     FLOAT
)
LANGUAGE SQL
AS
$$
BEGIN
    CALL MODEL_BIKE_OUTPUT!FORECAST(
        FORECASTING_PERIODS => :p_periods,
        CONFIG_OBJECT       => {'prediction_interval': 0.8}
    );

    LET res RESULTSET := (
        SELECT
            TS::DATE       AS ts,
            FORECAST       AS forecast,
            LOWER_BOUND    AS lower_bound,
            UPPER_BOUND    AS upper_bound
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        ORDER BY TS
    );

    RETURN TABLE(res);
END;
$$;


-- Procedure 2: On-Time Rate Forecast
CREATE OR REPLACE PROCEDURE SP_FORECAST_ON_TIME_RATE (p_periods INT DEFAULT 12)
RETURNS TABLE (
    ts              DATE,
    forecast        FLOAT,
    lower_bound     FLOAT,
    upper_bound     FLOAT
)
LANGUAGE SQL
AS
$$
BEGIN
    CALL MODEL_ON_TIME_RATE!FORECAST(
        FORECASTING_PERIODS => :p_periods,
        CONFIG_OBJECT       => {'prediction_interval': 0.8}
    );

    LET res RESULTSET := (
        SELECT
            TS::DATE       AS ts,
            FORECAST       AS forecast,
            LOWER_BOUND    AS lower_bound,
            UPPER_BOUND    AS upper_bound
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        ORDER BY TS
    );

    RETURN TABLE(res);
END;
$$;


-- Procedure 3: Task Duration Forecast (Multi-series)
CREATE OR REPLACE PROCEDURE SP_FORECAST_TASK_DURATION (p_periods INT DEFAULT 30)
RETURNS TABLE (
    series_id       STRING,
    ts              DATE,
    forecast        FLOAT,
    lower_bound     FLOAT,
    upper_bound     FLOAT
)
LANGUAGE SQL
AS
$$
BEGIN
    CALL MODEL_TASK_DURATION!FORECAST(
        FORECASTING_PERIODS => :p_periods,
        CONFIG_OBJECT       => {'prediction_interval': 0.8}
    );

    LET res RESULTSET := (
        SELECT
            SERIES_ID       AS series_id,
            TS::DATE        AS ts,
            FORECAST        AS forecast,
            LOWER_BOUND     AS lower_bound,
            UPPER_BOUND     AS upper_bound
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        ORDER BY SERIES_ID, TS
    );

    RETURN TABLE(res);
END;
$$;


-- Procedure 4: Department Throughput Forecast (Multi-series)
CREATE OR REPLACE PROCEDURE SP_FORECAST_DEPT_THROUGHPUT (p_periods INT DEFAULT 30)
RETURNS TABLE (
    series_id       STRING,
    ts              DATE,
    forecast        FLOAT,
    lower_bound     FLOAT,
    upper_bound     FLOAT
)
LANGUAGE SQL
AS
$$
BEGIN
    CALL MODEL_DEPT_THROUGHPUT!FORECAST(
        FORECASTING_PERIODS => :p_periods,
        CONFIG_OBJECT       => {'prediction_interval': 0.8}
    );

    LET res RESULTSET := (
        SELECT
            SERIES_ID       AS series_id,
            TS::DATE        AS ts,
            FORECAST        AS forecast,
            LOWER_BOUND     AS lower_bound,
            UPPER_BOUND     AS upper_bound
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        ORDER BY SERIES_ID, TS
    );

    RETURN TABLE(res);
END;
$$;
