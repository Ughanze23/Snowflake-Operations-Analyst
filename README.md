# VeloForge Operations Analyst — Snowflake Intelligence Platform

A two-product analytics platform built on Snowflake that gives VeloForge bicycle assembly managers instant, data-backed answers about their production floor — through a self-service chat app and a Slack-native AI agent.

---

## The Company

**VeloForge** is a bicycle manufacturer that assembles bikes across six specialized departments. Each bike moves through a 14-step sequential assembly line — from frame construction to final packaging — with every task logged in real time. Operations managers need fast visibility into throughput, delays, and workforce performance without writing SQL or switching tools.

---

## The Two Products

### Product 1 — Streamlit in Snowflake App
A self-service chat interface deployed inside Snowflake. Managers open it in Snowsight and ask questions about the assembly data in plain English. Cortex Analyst translates the question into SQL, executes it, and Cortex Complete narrates the results as a concise answer.

### Product 2 — OpsBike AI Slack Agent
A conversational operations analyst agent deployed on Slack via Snowflake MCP (Model Context Protocol). Production managers and supervisors ask questions directly in Slack and get data-backed answers without leaving the tools they already use. The agent goes beyond simple Q&A — it monitors thresholds, surfaces performance alerts, provides performance steeringa actions and generates 30-day forecasts.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Data Warehouse | Snowflake |
| Natural Language to SQL | Snowflake Cortex Analyst |
| Semantic Layer | Snowflake Semantic Model (YAML) |
| LLM for Answer Generation | Snowflake Cortex Complete (`SNOWFLAKE.CORTEX.COMPLETE`) |
| Entity Resolution | Snowflake Cortex Search |
| Statistical Forecasting | Snowflake ML.FORECAST |
| Self-Service App | Streamlit in Snowflake (SiS) |
| Slack Integration | Snowflake MCP (Model Context Protocol) |

### Snowflake Cortex Analyst
Translates natural language questions into SQL using the semantic model as schema context. Understands business terminology like "schedule variance", "on-time rate", and "cycle time" — generating accurate queries without the user needing to know the underlying tables.

### Semantic Model
`semantic_model.yaml` defines the business meaning of tables, columns, metrics, and relationships. It exposes pre-calculated measures like `ON_TIME_RATE`, `BIKE_CYCLE_TIME`, and `AVG_DELAY_LATE_ONLY` so Cortex Analyst answers operational questions accurately and consistently.

### Snowflake MCP
Connects the OpsBike AI agent to Slack. Users interact with the agent in natural language inside Slack channels or DMs. The agent calls Cortex Analyst, Cortex Search, Cortex Complete, and ML.FORECAST as tools depending on the question type.

---

## Entity Relationship Diagram

![ERD](erd.png)

---

## Database Schema

**Database:** `SNOWFLAKE_OPERATIONS_ANALYST` | **Schema:** `ANALYTICS`

### DEPARTMENT
6 rows — Assembly departments on the production floor.

| Column | Type | Description |
|---|---|---|
| dept_id | VARCHAR(10) | Abbreviated department code (`FRM`, `WHL`, `DRIV`, `FQC`, `PACK`, `RECV`) |
| description | VARCHAR(100) | Full department name (Frame, Wheel Assembly, Drivetrain, Final Assembly & QC, Packing & Shipping, Receiving) |

### EMPLOYEE
980 rows — Full workforce roster.

| Column | Type | Description |
|---|---|---|
| employee_id | VARCHAR(20) | Unique employee identifier |
| first_name | VARCHAR(50) | First name |
| last_name | VARCHAR(50) | Last name |
| email | VARCHAR(100) | Unique work email |
| gender | VARCHAR(10) | Gender |
| birthday | DATE | Date of birth (age derived at query time) |
| department_id | VARCHAR(10) | FK → DEPARTMENT.dept_id |

### TASK
14 rows — Every step in the bike assembly process.

| Column | Type | Description |
|---|---|---|
| task_id | VARCHAR(10) | Task identifier (T1–T14) |
| description | VARCHAR(500) | Task name (e.g. Frame Assembly, Fork Installation, Quality Check) |
| precedence | VARCHAR(500) | Which task(s) must be completed before this one |

**Task baseline durations:**

| Task | Description | Baseline |
|---|---|---|
| T1 | Frame Assembly | 35 min |
| T2 | Fork Installation | 15 min |
| T3 | Handlebar & Shifter Assembly | 20 min |
| T4 | Brake Lever Installation | 12 min |
| T5 | Wheel Assembly | 25 min |
| T6 | Tire & Tube Installation | 10 min |
| T7 | Derailleur & Chain | 20 min |
| T8 | Gear Shifter Adjustment | 15 min |
| T9 | Brake System Calibration | 18 min |
| T10 | Handlebar Grips | 8 min |
| T11 | Pedals & Crankset | 15 min |
| T12 | Seat & Seatpost | 10 min |
| T13 | Quality Check & Adjustment | 20 min |
| T14 | Packaging & Labeling | 12 min |

### TASK_LOG
86,450 rows — The core operational fact table. One row per task execution per bike per employee, covering 247 business days in 2023.

| Column | Type | Description |
|---|---|---|
| bike_unit_id | VARCHAR(20) | Unique bike identifier (e.g. `BU-2023-000001`) |
| task_date | DATE | Date the task was performed |
| start_time | TIME | When the employee started the task |
| scheduled_end_time | TIME | When the task was expected to finish |
| actual_end_time | TIME | When the task actually finished |
| task_id | VARCHAR(10) | FK → TASK.task_id |
| employee_id | VARCHAR(20) | FK → EMPLOYEE.employee_id |

**Derived metrics available via the semantic model:**

| Metric | Description |
|---|---|
| `TASK_DURATION` | Actual time spent on a task (minutes) |
| `SCHEDULE_VARIANCE_MIN` | Minutes early (negative) or late (positive) vs schedule |
| `ON_TIME_RATE` | % of tasks completed on or before scheduled end |
| `AVG_DELAY_LATE_ONLY` | Average delay for tasks that ran over (minutes) |
| `BIKE_CYCLE_TIME` | Wall-clock time from T1 start to T14 end for one bike |
| `DAILY_BIKE_OUTPUT` | Number of bikes completed per day |
| `MAX_OVER_RUN_BY_TASK` | Worst-case delay per task type |
| `TASK_DURATION_STDEV` | Standard deviation of task durations (consistency measure) |

---

## Product 1: Streamlit Chat App

The Streamlit in Snowflake app (`bike_operations_analyst_app`) provides a browser-based chat interface for self-service analytics.

**How it works:**
1. User types a question in the chat input
2. The question is sent to Cortex Analyst, which uses the semantic model to generate SQL
3. The SQL is executed against the Snowflake tables
4. Results are passed to `SNOWFLAKE.CORTEX.COMPLETE`, which narrates a concise answer
5. The answer, generated SQL, and raw results are all surfaced in the UI
6. Full conversation history is maintained so follow-up questions work in context

**Sample questions for the Streamlit app:**
- How many bikes did we complete last month?
- Which task has the worst on-time rate?
- What is the average task duration for Frame Assembly?
- Which department has the highest schedule variance?
- Who are the top 5 employees by tasks completed?

---

## Product 2: OpsBike AI Slack Agent

**OpsBike AI** is a Slack-native operations analyst agent deployed via Snowflake MCP. It covers 10 core responsibilities across three categories:

| Category | Responsibilities |
|---|---|
| **Descriptive** (what happened) | R1–R8: production, schedule, tasks, employees, departments, workforce, trends, process |
| **Prescriptive** (what to do) | R9: performance steering — threshold monitoring with tiered alerts |
| **Predictive** (what will happen) | R10: 30-day statistical forecasting via ML.FORECAST |

### Agent Tools

| Tool | Function | Used By |
|---|---|---|
| Cortex Analyst | Translates questions to SQL and executes them | R1–R9 |
| Cortex Complete | Generates natural language answers from SQL results | R1–R10 |
| Cortex Search | Resolves fuzzy names ("the handlebar task", "Eyde") to exact IDs before querying | R3, R4, R6, R8, R9 |
| ML.FORECAST | Generates 30-day time-series forecasts with confidence intervals | R10 only |

### Performance Steering (R9)

When a manager asks for a health check — or flags a potential issue — the agent runs five threshold SQL queries simultaneously against the live data. Cortex Complete then reasons over all five result sets together and composes a single tiered response: **Critical**, **Warning**, or **Healthy** for each area.

**The five thresholds monitored:**

| # | Level | Metric | Trigger condition |
|---|---|---|---|
| T-1 | Task | On-time completion rate | Falls below 90% (trailing 7 days) |
| T-2 | Task | Average duration vs baseline | Exceeds 120% of its defined baseline (trailing 7 days) |
| T-3 | Employee | Utilization rate | Below 60% of the 540-minute shift (prior business day) |
| T-4 | Department | Weekly throughput | Drops more than 15% vs the prior week |
| T-5 | Production | Daily bike output | Falls below the 25-bike daily target (trailing 7 days) |

**How the agent generates recommendations:**

1. Cortex Analyst runs all five threshold queries in parallel and returns five result sets
2. Cortex Complete reads every result set together and classifies each finding as Critical (significant breach), Warning (mild breach or approaching threshold), or Healthy (within limits)
3. For every flagged item, the agent cites the exact metric value and threshold that triggered it, then surfaces a specific, data-backed suggestion using measured language ("consider", "worth reviewing", "may indicate") — never directives
4. Items that are within healthy limits are listed explicitly so managers know what is not a concern

**Example alert output:**

```
PERFORMANCE ALERT — [date]

CRITICAL:
  T8 (Gear Shifter Adjustment) — on-time rate 76% [threshold: 90%]
  → Review Drivetrain employees assigned to T8 this week.
    Consider pairing lower performers with higher-performing peers next shift.

WARNING:
  Daily output — 22 bikes on Tuesday [baseline: 25]
  → Check whether T1 (Frame Assembly) was understaffed.
    Tuesday had fewer FRM employees active than the weekly average.

HEALTHY:
  T1, T2, T3, T4, T5, T6, T7, T9, T10, T11, T12, T13, T14 — all clear.
```

**Guardrails applied to every recommendation:**
- Always cites the metric value and threshold that triggered the alert
- Never recommends actions based on personal employee data beyond task performance
- Never presents a recommendation as a directive — always as a suggestion
- If all thresholds are healthy, says so clearly rather than inventing concerns

### Forecasting (R10)
Generates 30-day projections for daily bike output, weekly on-time rate, task duration trends, and department throughput. All forecasts include confidence intervals and are clearly labelled as estimates.

### Sample questions for the Slack agent:
- Are there any performance issues I should know about this week?
- Which department is the bottleneck right now?
- Who are the slowest employees in the Drivetrain team?
- How many bikes are we likely to produce next month?
- Is our on-time rate improving or getting worse over the year?
- Flag anything underperforming — give me a full health check
- What tasks can run in parallel during assembly?
- Which employees have on-time rates below 80%?
- Forecast Drivetrain department throughput for the next 4 weeks
- How did Q3 compare to Q1 in output?

---

## Setup

### 1. Snowflake Data Layer
Run `DDL.sql` to create the database, schema, tables, and stage:
```sql
-- Creates SNOWFLAKE_OPERATIONS_ANALYST database, ANALYTICS schema,
-- DEPARTMENT, EMPLOYEE, TASK, TASK_LOG tables, and csv_stage
```

Upload CSV files from the `data/` folder to the internal stage, then load:
```sql
COPY INTO DEPARTMENT FROM @csv_stage/department.csv;
COPY INTO EMPLOYEE FROM @csv_stage/employee.csv;
COPY INTO TASK FROM @csv_stage/task.csv;
COPY INTO TASK_LOG FROM @csv_stage/task_log.csv;
```

### 2. Semantic Model
Create a Snowflake Semantic View using `semantic_model.yaml` in the `ANALYTICS` schema.

### 3. Streamlit App
Deploy `bike_operations_analyst_app` as a Streamlit in Snowflake app:
- In Snowsight: **Projects → Streamlit → + Streamlit App**
- Set database/schema to `SNOWFLAKE_OPERATIONS_ANALYST.ANALYTICS`
- Paste the app code and click **Run**

### 4. Forecasting Views (required for R10)
Create the four ML.FORECAST input views defined in `Agent_instructions/agent_design_document.md` (`V_DAILY_BIKE_OUTPUT`, `V_WEEKLY_ONTIME_RATE`, `V_TASK_DURATION_DAILY`, `V_DEPT_DAILY_THROUGHPUT`).

### 5. Slack Agent
Configure the OpsBike AI agent in Snowflake Intelligence using the persona and tool definitions in `Agent_instructions/agent_design_document.md`, then connect to Slack via the Snowflake MCP integration.
