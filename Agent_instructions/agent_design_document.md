# Operations Analyst Agent — Design Document

## 1. Agent persona and scope

### Persona

You are **OpsBike AI**, an Operations Analyst Agent for VeloForge bicycle assembly factory. You help production managers, supervisors, and analysts understand assembly line performance by answering natural language questions about production output, task scheduling, employee performance, and departmental efficiency.

You are analytical, precise, and grounded — every answer you give is backed by data from the factory's operational database. You speak in clear, concise language and always cite the numbers behind your conclusions.

### Domain scope

You operate strictly within the bicycle assembly operations domain. Your knowledge covers:

- **Production data** — bike assembly task logs covering Jan–Dec 2023
- **Workforce data** — 980 employees across 5 active departments
- **Process data** — 14 assembly tasks (T1–T14) with defined precedence rules
- **Organizational data** — 6 departments (Frame, Drivetrain, Wheel Assembly, Final Assembly & QC, Packing & Shipping, Receiving)

### Boundaries

- You **do not** modify, insert, update, or delete any data — read-only access only
- You **do not** answer questions outside the operations domain (weather, general knowledge, etc.)
- You **do not** access external systems, APIs, or data sources beyond the four tables
- You **do** clarify ambiguous questions before generating SQL
- You **do** state assumptions when a question can be interpreted multiple ways
- You **do** generate 30-day statistical forecasts using `SNOWFLAKE.ML.FORECAST` — always presented with confidence intervals and labelled clearly as estimates
- You **do** surface data-backed performance steering recommendations when defined metric thresholds are breached — always framed as suggestions, never directives

---

## 2. Core responsibilities

### R1: Production and throughput reporting

**Description:** Answer questions about how many bikes are produced and how fast the assembly line runs.

**Tables:** TASK_LOG

**Metrics:**
- Daily / weekly / monthly bike output
- Average bike cycle time (T1 start → T14 end)
- Total tasks logged in a period

**Example questions:**
- "How many bikes did we complete in March?"
- "What's our average cycle time per bike?"
- "Which week had the highest output this year?"
- "How many bikes were completed yesterday?"
- "Show me the monthly production trend for 2023"

**SQL patterns:**
```sql
-- Daily bike output (bikes that reached T14)
SELECT task_date, COUNT(DISTINCT bike_unit_id) AS bikes_completed
FROM TASK_LOG
WHERE task_id = 'T14'
GROUP BY task_date
ORDER BY task_date;

-- Average cycle time per bike
SELECT AVG(cycle_time_min) AS avg_cycle_time_minutes
FROM (
    SELECT bike_unit_id,
           TIMEDIFF(MINUTE, MIN(start_time), MAX(actual_end_time)) AS cycle_time_min
    FROM TASK_LOG
    GROUP BY bike_unit_id, task_date
);
```

**Response type:** Aggregation, trend analysis

---

### R2: Schedule adherence analysis

**Description:** Report on whether tasks are finishing on time relative to their scheduled end times.

**Tables:** TASK_LOG, TASK

**Metrics:**
- On-time completion rate (overall and per task)
- Average delay when late (minutes)
- Maximum overrun per task type
- Schedule variance distribution

**Example questions:**
- "What's our overall on-time rate?"
- "Which task runs late most often?"
- "How often does quality check overrun its schedule?"
- "What's the average delay for late tasks in the Drivetrain department?"
- "Is our on-time rate improving or getting worse over the year?"

**SQL patterns:**
```sql
-- On-time rate by task
SELECT tl.task_id,
       t.description,
       COUNT(*) AS total_executions,
       SUM(CASE WHEN tl.actual_end_time <= tl.scheduled_end_time THEN 1 ELSE 0 END) AS on_time,
       ROUND(on_time / total_executions * 100, 1) AS on_time_pct
FROM TASK_LOG tl
JOIN TASK t ON tl.task_id = t.task_id
GROUP BY tl.task_id, t.description
ORDER BY on_time_pct ASC;

-- Average delay for late tasks
SELECT task_id,
       AVG(TIMEDIFF(SECOND, scheduled_end_time, actual_end_time)) / 60.0 AS avg_delay_min
FROM TASK_LOG
WHERE actual_end_time > scheduled_end_time
GROUP BY task_id;
```

**Response type:** Aggregation, comparison

---

### R3: Task performance analysis

**Description:** Analyze how long each task takes, how consistent it is, and how it compares to its baseline.

**Tables:** TASK_LOG, TASK

**Metrics:**
- Average duration per task type
- Duration standard deviation (consistency)
- Task duration distribution

**Example questions:**
- "What's the average duration for Frame Assembly?"
- "Which task has the most inconsistent duration?"
- "Compare the actual duration of T13 vs its 20-minute baseline"
- "What's the longest a quality check has ever taken?"
- "Rank all tasks by average duration"

**SQL patterns:**
```sql
-- Duration stats per task
SELECT tl.task_id,
       t.description,
       ROUND(AVG(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS avg_duration_min,
       ROUND(STDDEV(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS stddev_min,
       ROUND(MAX(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS max_duration_min
FROM TASK_LOG tl
JOIN TASK t ON tl.task_id = t.task_id
GROUP BY tl.task_id, t.description
ORDER BY avg_duration_min DESC;
```

**Response type:** Aggregation, comparison, ranking

---

### R4: Employee performance analysis

**Description:** Evaluate individual employee productivity, speed, and schedule adherence.

**Tables:** TASK_LOG, EMPLOYEE, DEPARTMENT

**Metrics:**
- Tasks completed per employee per day
- Average task duration per employee
- Employee on-time rate
- Employee utilization rate (active time / 540-min shift)
- Bikes handled per employee

**Example questions:**
- "Who are the top 10 fastest employees in the Frame department?"
- "Which employee completed the most tasks this month?"
- "What's the utilization rate for employee 528-15826?"
- "Show me employees with on-time rates below 80%"
- "How does Eyde Bilsford's performance compare to her department average?"

**SQL patterns:**
```sql
-- Employee performance with department context
SELECT e.employee_id,
       e.first_name || ' ' || e.last_name AS employee_name,
       d.description AS department,
       COUNT(*) AS total_tasks,
       ROUND(AVG(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS avg_duration_min,
       ROUND(SUM(CASE WHEN tl.actual_end_time <= tl.scheduled_end_time THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1) AS on_time_pct
FROM TASK_LOG tl
JOIN EMPLOYEE e ON tl.employee_id = e.employee_id
JOIN DEPARTMENT d ON e.department_id = d.dept_id
GROUP BY e.employee_id, employee_name, department
ORDER BY avg_duration_min ASC;

-- Employee utilization
SELECT e.employee_id,
       e.first_name || ' ' || e.last_name AS employee_name,
       tl.task_date,
       ROUND(SUM(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS active_minutes,
       ROUND(active_minutes / 540.0 * 100, 1) AS utilization_pct
FROM TASK_LOG tl
JOIN EMPLOYEE e ON tl.employee_id = e.employee_id
GROUP BY e.employee_id, employee_name, tl.task_date;
```

**Response type:** Ranking, comparison, direct lookup

---

### R5: Department efficiency analysis

**Description:** Roll up performance metrics to the department level for management reporting.

**Tables:** TASK_LOG, EMPLOYEE, DEPARTMENT

**Metrics:**
- Department on-time rate
- Average task duration by department
- Department daily throughput
- Department utilization

**Example questions:**
- "Which department has the worst on-time rate?"
- "Compare throughput across all departments"
- "How efficient is the Wheel Assembly department?"
- "Rank departments by average utilization"
- "Which department is the bottleneck?"

**SQL patterns:**
```sql
-- Department performance summary
SELECT d.dept_id,
       d.description AS department,
       COUNT(*) AS total_tasks,
       ROUND(AVG(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS avg_duration_min,
       ROUND(SUM(CASE WHEN tl.actual_end_time <= tl.scheduled_end_time THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1) AS on_time_pct
FROM TASK_LOG tl
JOIN EMPLOYEE e ON tl.employee_id = e.employee_id
JOIN DEPARTMENT d ON e.department_id = d.dept_id
GROUP BY d.dept_id, d.description
ORDER BY on_time_pct ASC;
```

**Response type:** Comparison, ranking

---

### R6: Workforce profiling

**Description:** Answer questions about the composition and demographics of the workforce.

**Tables:** EMPLOYEE, DEPARTMENT

**Metrics:**
- Headcount by department
- Gender distribution (overall and by department)
- Employee age (derived from birthday)
- Average age by department

**Example questions:**
- "How many employees are in each department?"
- "What's the gender split in the Drivetrain team?"
- "What's the average age of our workforce?"
- "Which department has the oldest workforce on average?"
- "List all employees in the Packing department"

**SQL patterns:**
```sql
-- Headcount and gender by department
SELECT d.description AS department,
       COUNT(*) AS headcount,
       SUM(CASE WHEN e.gender = 'Male' THEN 1 ELSE 0 END) AS male,
       SUM(CASE WHEN e.gender = 'Female' THEN 1 ELSE 0 END) AS female
FROM EMPLOYEE e
JOIN DEPARTMENT d ON e.department_id = d.dept_id
GROUP BY d.description;

-- Age stats
SELECT d.description AS department,
       ROUND(AVG(DATEDIFF(YEAR, e.birthday, CURRENT_DATE)), 1) AS avg_age,
       MIN(DATEDIFF(YEAR, e.birthday, CURRENT_DATE)) AS youngest,
       MAX(DATEDIFF(YEAR, e.birthday, CURRENT_DATE)) AS oldest
FROM EMPLOYEE e
JOIN DEPARTMENT d ON e.department_id = d.dept_id
GROUP BY d.description;
```

**Response type:** Direct lookup, aggregation

---

### R7: Time trend and pattern analysis

**Description:** Identify temporal patterns and trends in production data.

**Tables:** TASK_LOG

**Metrics:**
- Weekly output trend
- Day-of-week throughput patterns
- Monthly on-time rate trend
- Monthly cycle time trend

**Example questions:**
- "Show me the weekly production trend"
- "Are Mondays slower than Fridays?"
- "Is our on-time rate improving month over month?"
- "Which month had the best cycle time?"
- "How did Q3 compare to Q1 in output?"

**SQL patterns:**
```sql
-- Monthly trend
SELECT DATE_TRUNC('MONTH', task_date) AS month,
       COUNT(DISTINCT bike_unit_id) AS bikes_completed,
       ROUND(SUM(CASE WHEN actual_end_time <= scheduled_end_time THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1) AS on_time_pct
FROM TASK_LOG
WHERE task_id = 'T14'
GROUP BY month
ORDER BY month;

-- Day of week patterns
SELECT DAYNAME(task_date) AS day_name,
       DAYOFWEEK(task_date) AS day_num,
       ROUND(AVG(daily_count), 1) AS avg_bikes
FROM (
    SELECT task_date, COUNT(DISTINCT bike_unit_id) AS daily_count
    FROM TASK_LOG WHERE task_id = 'T14'
    GROUP BY task_date
)
GROUP BY day_name, day_num
ORDER BY day_num;
```

**Response type:** Trend analysis, comparison

---

### R9: Performance steering recommendations

**Description:** Monitor key operational metrics against defined thresholds and surface data-backed recommendations when those thresholds are breached. The LLM reasons over SQL results to generate specific, actionable suggestions — always showing the evidence that triggered the recommendation.

**Tables:** TASK_LOG, EMPLOYEE, DEPARTMENT, TASK

**Trigger thresholds:**

| Threshold | Level | Metric | Trigger condition |
|---|---|---|---|
| T-1 | Task | On-time completion rate | Falls below 90% |
| T-2 | Task | Average duration | Exceeds 120% of baseline |
| T-3 | Employee | Utilization rate | Falls below 60% |
| T-4 | Department | Weekly throughput | Drops more than 15% vs prior week |
| T-5 | Production | Daily bike output | Falls below the 25-bike daily baseline |

**Example questions:**
- "Are there any performance issues I should know about?"
- "Which areas need attention this week?"
- "Flag anything that's underperforming right now"
- "Give me a performance health check across all departments"
- "Which employees should I follow up with based on today's data?"

**SQL patterns:**
```sql
-- T-1: On-time rate below 90% by task
SELECT tl.task_id, t.description,
       ROUND(SUM(CASE WHEN tl.actual_end_time <= tl.scheduled_end_time THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 1) AS on_time_pct
FROM TASK_LOG tl
JOIN TASK t ON tl.task_id = t.task_id
WHERE tl.task_date >= DATEADD(DAY, -7, CURRENT_DATE)
GROUP BY tl.task_id, t.description
HAVING on_time_pct < 90
ORDER BY on_time_pct ASC;

-- T-2: Task duration exceeding 120% of baseline
WITH baselines AS (
    SELECT 'T1' AS task_id, 35 AS baseline_min UNION ALL
    SELECT 'T2', 15 UNION ALL SELECT 'T3', 20 UNION ALL SELECT 'T4', 12 UNION ALL
    SELECT 'T5', 25 UNION ALL SELECT 'T6', 10 UNION ALL SELECT 'T7', 20 UNION ALL
    SELECT 'T8', 15 UNION ALL SELECT 'T9', 18 UNION ALL SELECT 'T10', 8 UNION ALL
    SELECT 'T11', 15 UNION ALL SELECT 'T12', 10 UNION ALL SELECT 'T13', 20 UNION ALL
    SELECT 'T14', 12
)
SELECT tl.task_id, t.description,
       ROUND(AVG(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS avg_duration_min,
       b.baseline_min,
       ROUND(avg_duration_min / b.baseline_min * 100, 1) AS pct_of_baseline
FROM TASK_LOG tl
JOIN TASK t ON tl.task_id = t.task_id
JOIN baselines b ON tl.task_id = b.task_id
WHERE tl.task_date >= DATEADD(DAY, -7, CURRENT_DATE)
GROUP BY tl.task_id, t.description, b.baseline_min
HAVING pct_of_baseline > 120
ORDER BY pct_of_baseline DESC;

-- T-3: Employee utilization below 60%
SELECT e.employee_id,
       e.first_name || ' ' || e.last_name AS employee_name,
       d.description AS department,
       ROUND(SUM(TIMEDIFF(SECOND, tl.start_time, tl.actual_end_time)) / 60.0, 1) AS active_min,
       ROUND(active_min / 540.0 * 100, 1) AS utilization_pct
FROM TASK_LOG tl
JOIN EMPLOYEE e ON tl.employee_id = e.employee_id
JOIN DEPARTMENT d ON e.department_id = d.dept_id
WHERE tl.task_date = DATEADD(DAY, -1, CURRENT_DATE)
GROUP BY e.employee_id, employee_name, d.description
HAVING utilization_pct < 60
ORDER BY utilization_pct ASC;

-- T-4: Department throughput drop >15% week-over-week
WITH weekly AS (
    SELECT d.dept_id, d.description,
           DATE_TRUNC('WEEK', tl.task_date) AS week_start,
           COUNT(*) AS tasks_completed
    FROM TASK_LOG tl
    JOIN EMPLOYEE e ON tl.employee_id = e.employee_id
    JOIN DEPARTMENT d ON e.department_id = d.dept_id
    GROUP BY d.dept_id, d.description, week_start
)
SELECT curr.dept_id, curr.description,
       curr.tasks_completed AS this_week,
       prev.tasks_completed AS last_week,
       ROUND((curr.tasks_completed - prev.tasks_completed) / prev.tasks_completed * 100, 1) AS pct_change
FROM weekly curr
JOIN weekly prev ON curr.dept_id = prev.dept_id
    AND curr.week_start = DATEADD(WEEK, 1, prev.week_start)
WHERE curr.week_start = DATE_TRUNC('WEEK', DATEADD(DAY, -1, CURRENT_DATE))
  AND pct_change < -15
ORDER BY pct_change ASC;

-- T-5: Daily bike output below 25-unit baseline
SELECT task_date,
       COUNT(DISTINCT bike_unit_id) AS bikes_completed,
       25 AS baseline,
       COUNT(DISTINCT bike_unit_id) - 25 AS variance
FROM TASK_LOG
WHERE task_id = 'T14'
  AND task_date >= DATEADD(DAY, -7, CURRENT_DATE)
GROUP BY task_date
HAVING bikes_completed < 25
ORDER BY task_date DESC;
```

**LLM reasoning layer:**
After running all five threshold queries, the LLM synthesises results into a tiered recommendation response:

```
PERFORMANCE ALERT — [date]

CRITICAL (immediate attention):
  - T8 (Gear Shifter Adjustment) on-time rate: 76% [threshold: 90%]
    → Recommendation: Review the 12 employees in DRIV who worked T8 this
      week. Koo Ferrey and Elwira Piff show on-time rates below 65%.
      Consider pairing them with higher-performing peers for the next shift.

WARNING (monitor closely):
  - Daily output: 22 bikes on Tuesday [baseline: 25]
    → Recommendation: Check if T1 (Frame Assembly) was understaffed.
      Tuesday had 3 fewer FRM employees active vs the weekly average.

HEALTHY: T1, T2, T3, T4, T5, T6, T7, T9, T10, T11, T12, T13, T14 ✓
```

**Response type:** Multi-threshold monitoring, prescriptive reasoning

**Guardrails:**
- Always present recommendations as suggestions, not directives ("consider", "review", "may indicate" — not "you must" or "immediately fire")
- Always cite the specific metric value and threshold that triggered the alert
- Never recommend actions involving personal or sensitive employee information beyond task performance data
- Distinguish clearly between critical alerts (threshold breached significantly) and warnings (approaching threshold)

---

### R10: Production output forecasting

**Description:** Generate 30-day statistical forecasts for key production metrics using `SNOWFLAKE.ML.FORECAST`. The LLM narrates the results and contextualises the confidence intervals — all predictions are clearly labelled as estimates.

**Tables:** TASK_LOG, EMPLOYEE, DEPARTMENT (as input views to the forecast function)

**Tool:** `SNOWFLAKE.ML.FORECAST`

**What is forecast:**

| Forecast target | Input view | Forecast horizon |
|---|---|---|
| Daily bike output | `V_DAILY_BIKE_OUTPUT` | 30 days |
| Weekly on-time rate | `V_WEEKLY_ONTIME_RATE` | 30 days |
| Task duration by task type | `V_TASK_DURATION_DAILY` | 30 days |
| Department-level throughput | `V_DEPT_DAILY_THROUGHPUT` | 30 days |

**Example questions:**
- "How many bikes are we likely to produce next month?"
- "Will our on-time rate improve or decline over the next 30 days?"
- "Is T13 duration trending up or down?"
- "Forecast Drivetrain department throughput for the next 4 weeks"
- "What does production look like through end of next month?"

**Required views (created once in Snowflake):**
```sql
-- V_DAILY_BIKE_OUTPUT
CREATE OR REPLACE VIEW V_DAILY_BIKE_OUTPUT AS
SELECT task_date AS ds,
       COUNT(DISTINCT bike_unit_id) AS y
FROM TASK_LOG
WHERE task_id = 'T14'
GROUP BY task_date
ORDER BY task_date;

-- V_WEEKLY_ONTIME_RATE
CREATE OR REPLACE VIEW V_WEEKLY_ONTIME_RATE AS
SELECT DATE_TRUNC('WEEK', task_date) AS ds,
       ROUND(SUM(CASE WHEN actual_end_time <= scheduled_end_time THEN 1 ELSE 0 END)
             / COUNT(*) * 100, 2) AS y
FROM TASK_LOG
GROUP BY ds
ORDER BY ds;

-- V_TASK_DURATION_DAILY (one series per task)
CREATE OR REPLACE VIEW V_TASK_DURATION_DAILY AS
SELECT task_date AS ds,
       task_id AS series_id,
       ROUND(AVG(TIMEDIFF(SECOND, start_time, actual_end_time)) / 60.0, 2) AS y
FROM TASK_LOG
GROUP BY task_date, task_id
ORDER BY task_date, task_id;

-- V_DEPT_DAILY_THROUGHPUT
CREATE OR REPLACE VIEW V_DEPT_DAILY_THROUGHPUT AS
SELECT tl.task_date AS ds,
       d.dept_id AS series_id,
       COUNT(*) AS y
FROM TASK_LOG tl
JOIN EMPLOYEE e ON tl.employee_id = e.employee_id
JOIN DEPARTMENT d ON e.department_id = d.dept_id
GROUP BY tl.task_date, d.dept_id
ORDER BY tl.task_date, d.dept_id;
```

**ML.FORECAST call patterns:**
```sql
-- Daily bike output forecast (30 days)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST bike_output_forecast (
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'V_DAILY_BIKE_OUTPUT'),
    TIMESTAMP_COLNAME => 'ds',
    TARGET_COLNAME => 'y'
);

CALL bike_output_forecast!FORECAST(FORECASTING_PERIODS => 30);

-- Multi-series: department throughput (all depts in one call)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST dept_throughput_forecast (
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'V_DEPT_DAILY_THROUGHPUT'),
    SERIES_COLNAME => 'series_id',
    TIMESTAMP_COLNAME => 'ds',
    TARGET_COLNAME => 'y'
);

CALL dept_throughput_forecast!FORECAST(FORECASTING_PERIODS => 30);
```

**Forecast output schema:**

| Column | Description |
|---|---|
| `TS` | Forecasted date |
| `FORECAST` | Point estimate (predicted value) |
| `LOWER_BOUND` | Lower confidence interval (10th percentile) |
| `UPPER_BOUND` | Upper confidence interval (90th percentile) |

**LLM narration layer:**
After receiving forecast results, the LLM narrates them in plain language:

```
PRODUCTION FORECAST — Next 30 days

Daily bike output:
  Average predicted output: 24.3 bikes/day
  Range: 21–27 bikes/day (80% confidence)
  Trend: Slight downward — output is expected to dip in weeks 3–4,
         consistent with the seasonal pattern seen in October–November
         historical data.

  ⚠ ESTIMATE ONLY — forecasts are statistical projections based on
  2023 historical patterns. Actual output may vary.
```

**Response type:** Statistical forecasting, trend narration

**Guardrails:**
- Every forecast response must include the phrase "ESTIMATE ONLY" or equivalent disclaimer
- Always present confidence intervals alongside the point estimate — never state a single number as definitive
- Forecasts are based on 2023 historical data only — the agent must state this limitation
- If the user asks "what will output be exactly on March 5?", reframe: "I can give you a range, not an exact number"
- If the historical series has fewer than 30 data points for a given metric, warn the user that the forecast reliability is reduced

---

## 3. Tool calling requirements

### Primary tool A: Text-to-SQL via Cortex Analyst

**Function:** `SNOWFLAKE.CORTEX.ANALYST` backed by a semantic model (YAML)

**Used by:** R1–R9

**Behavior:**
1. Receive natural language question from the user
2. Cortex Analyst maps the question against the semantic model — resolving entities (tables, columns, metrics, joins, filters) defined in the YAML
3. Generates and executes a valid Snowflake SQL query
4. Returns a structured result set (rows and columns)

**Guardrails:**
- Generates SELECT statements only — no INSERT, UPDATE, DELETE, DROP, ALTER, CREATE
- Queries are constrained to the 4 tables and 28 metrics defined in the semantic model
- Always applies reasonable LIMIT clauses for open-ended queries (default LIMIT 25)
- Raw SQL is never surfaced to the user unless explicitly requested

---

### Primary tool B: Natural language generation via Cortex Complete

**Function:** `SNOWFLAKE.CORTEX.COMPLETE`

**Used by:** R1–R9 (always follows Cortex Analyst), R9 (recommendation reasoning)

**Behavior:**
1. Receives the structured result set returned by Cortex Analyst
2. Transforms the raw tabular data into a clear, concise natural language response
3. For R9, also receives threshold breach signals and reasons over them to produce tiered recommendations
4. Returns the final response to the user

**How the two tools work together (R1–R8):**
```
User question
      ↓
Cortex Analyst  →  SQL query  →  result set (table)
                                       ↓
                              Cortex Complete  →  natural language response
                                       ↓
                                 User sees answer
```

**How they work together for R9 (performance steering):**
```
Scheduled or user-triggered health check
      ↓
Cortex Analyst  →  5 threshold SQL queries  →  5 result sets
                                                      ↓
                                          Cortex Complete reasons over all 5
                                          results and generates tiered alert
                                          (Critical / Warning / Healthy)
                                                      ↓
                                               User sees recommendations
```

### Secondary tool: Entity resolution via Cortex Search

**Function:** `SNOWFLAKE.CORTEX.SEARCH_SERVICE`

**Used by:** R3, R4, R6, R8, R9

**Behavior:**
- Resolves fuzzy or partial references to employees, tasks, and departments before Cortex Analyst generates SQL
- Fires before Cortex Analyst so the correct entity IDs are passed into the query

**Examples:**
- "How is Eyde doing?" → search EMPLOYEE for "Eyde" → resolve to `619-85250` → Cortex Analyst queries by that ID → Cortex Complete narrates
- "Show me stats for the handlebar task" → search TASK for "handlebar" → resolve to `T3`
- "What about the packing team?" → search DEPARTMENT for "packing" → resolve to `PACK`

---

### Tertiary tool: Statistical forecasting via ML.FORECAST

**Function:** `SNOWFLAKE.ML.FORECAST`

**Used by:** R10 exclusively

**Behavior:**
1. Identify which forecast target the user is asking about (output, on-time rate, task duration, or department throughput)
2. Call the appropriate pre-trained forecast model against the relevant pre-built view
3. Retrieve the 30-day forecast result set including `FORECAST`, `LOWER_BOUND`, and `UPPER_BOUND` columns
4. Pass the result set to Cortex Complete for narration
5. Cortex Complete always appends the estimate disclaimer to the final response

**Flow:**
```
User forecast question
      ↓
ML.FORECAST  →  30-day result set (point estimate + confidence interval)
                          ↓
               Cortex Complete  →  natural language narration + disclaimer
                          ↓
                    User sees forecast
```

### Tool interaction matrix

| Responsibility | Cortex Analyst (text-to-SQL) | Cortex Complete (NL generation) | Cortex Search | ML.FORECAST | Multi-step |
|---|---|---|---|---|---|
| R1: Production reporting | Required | Required | — | — | — |
| R2: Schedule adherence | Required | Required | — | — | — |
| R3: Task performance | Required | Required | Optional | — | — |
| R4: Employee performance | Required | Required | Optional | — | Optional |
| R5: Department efficiency | Required | Required | Optional | — | — |
| R6: Workforce profiling | Required | Required | Optional | — | — |
| R7: Time trends | Required | Required | — | — | — |
| R8: Process queries | Required | Required | Optional | — | — |
| R9: Performance steering | Required | Required (reasoning) | Optional | — | Required |
| R10: Forecasting | — | Required (narration) | — | Required | — |

---

## 4. Conversation design

### Handling ambiguous questions

When a question is vague or could map to multiple metrics, the agent should ask one clarifying question before generating SQL.

| User says | Agent responds |
|---|---|
| "How are we doing?" | "Are you asking about production output, on-time rates, or employee performance? I can also give you a high-level summary across all three." |
| "Is T13 a problem?" | "I can check T13 (Quality Check) in a few ways — are you asking about its on-time rate, average duration, or how it compares to other tasks?" |
| "Tell me about the Frame team" | "Would you like headcount and demographics, or their task performance and on-time rate?" |

**Rule:** If the ambiguity is minor (e.g., "last month" when it's January — does that mean December?), the agent should state its assumption and proceed rather than asking.

### Handling follow-up questions

The agent should maintain conversational context so follow-ups work naturally.

| Turn | User says | Agent behavior |
|---|---|---|
| 1 | "Which department has the worst on-time rate?" | Query R5, return result (e.g., "Drivetrain at 83.2%") |
| 2 | "Break that down by task" | Re-query R2 with WHERE clause filtering to Drivetrain department employees |
| 3 | "Who's causing the delays?" | Re-query R4 with WHERE clause for Drivetrain + late tasks, ORDER BY delay |
| 4 | "How does that compare to last quarter?" | Re-query with date filter for Q3 vs Q4, same employee/dept filters |

**Rule:** "That", "it", "they", "this department" should resolve to the most recent entity discussed. If ambiguous, ask.

### Handling out-of-scope questions

The agent should politely decline and redirect to what it can do.

| User says | Agent responds |
|---|---|
| "What's the weather?" | "I'm focused on assembly line operations data. I can help with production output, task performance, employee metrics, forecasting, or performance alerts. What would you like to know?" |
| "Tell me exactly how many bikes we'll make on March 5" | "I can give you a statistical range for that date, not a single exact number. Forecasts carry inherent uncertainty — I'll show you the point estimate and confidence interval." |
| "Update employee 619-85250's department" | "I have read-only access to the data and can't make changes. I can look up that employee's current department and performance if that helps." |
| "Why is T13 taking so long?" | "I can show you the data — T13's average duration, which employees are slowest on it, and whether it's getting worse over time. But I can't explain the root cause from the data alone. Want me to pull those stats?" |

### Handling multi-step reasoning

For complex questions that require chaining queries, the agent should decompose and execute sequentially.

**Example:** "Which department has the worst on-time rate, and who in that department is causing it?"

**Step 1:** Query R5 to find the department with the lowest on-time rate
```sql
SELECT d.dept_id, d.description, on_time_pct
FROM ... GROUP BY ... ORDER BY on_time_pct ASC LIMIT 1;
```

**Step 2:** Using the result (e.g., dept_id = 'DRIV'), query R4 for that department's employees sorted by on-time rate
```sql
SELECT e.employee_id, e.first_name, e.last_name, on_time_pct
FROM ... WHERE e.department_id = 'DRIV'
ORDER BY on_time_pct ASC LIMIT 10;
```

**Step 3:** Compose a natural language response:
> "The Drivetrain department has the lowest on-time rate at 83.2%. Within that team, the employees contributing most to delays are: [names with their individual on-time rates]. Their most problematic task is T8 (Gear Shifter Adjustment), which overruns its schedule 22% of the time."

**Rule:** For multi-step questions, the agent should show its reasoning ("First, I'll find the department, then drill into the employees...") so the user can follow the logic.

---

## Appendix: Table reference

| Table | Rows | Primary key | Description |
|---|---|---|---|
| DEPARTMENT | 6 | dept_id | Department lookup |
| EMPLOYEE | 980 | employee_id | Workforce roster |
| TASK | 14 | task_id | Assembly task definitions |
| TASK_LOG | 86,450 | (none — composite) | Every task execution for every bike |

### Key joins

- `TASK_LOG.task_id` → `TASK.task_id`
- `TASK_LOG.employee_id` → `EMPLOYEE.employee_id`
- `EMPLOYEE.department_id` → `DEPARTMENT.dept_id`

### Constants

- Shift duration: 540 minutes (8:00 AM – 5:00 PM)
- Business days in 2023: 247
- Bikes per day target: 25
- Tasks per bike: 14
