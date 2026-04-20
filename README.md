# Snowflake Operations Analyst — Bike Assembly Intelligence Platform

A conversational analytics application built on Snowflake that allows operations managers at a fictitious bike manufacturing company to ask natural language questions about their assembly floor data — and get instant, data-backed answers.

---

## The Company

**VeloForge** is a mid-sized bicycle manufacturer that assembles bikes across multiple specialized departments. Each bike moves through a sequential assembly line — from frame construction to final quality checks — with tasks logged in real time by department employees. Operations managers need fast visibility into throughput, delays, and workforce performance without writing SQL.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Data Warehouse | Snowflake |
| Natural Language to SQL | Snowflake Cortex Analyst |
| Semantic Layer | Snowflake Semantic Model (YAML) |
| LLM for Answer Generation | Snowflake Cortex (`SNOWFLAKE.CORTEX.COMPLETE`) |
| Frontend | Streamlit in Snowflake (SiS) |

### Snowflake Cortex Analyst
Cortex Analyst translates plain English questions into SQL using the semantic model as its schema context. It understands business terminology (e.g. "schedule variance", "cycle time") and generates accurate queries without the user needing to know the underlying table structure.

### Semantic Model
The semantic model (`semantic_model.yaml`) defines the business meaning of tables, columns, metrics, and their relationships. It exposes pre-calculated measures like `ON_TIME_RATE`, `BIKE_CYCLE_TIME`, and `AVG_DELAY_LATE_ONLY` so Cortex Analyst can answer operational questions accurately and consistently.

---

## Entity Relationship Diagram

![ERD](erd.png)

---

## Database Schema

Database: `SNOWFLAKE_OPERATIONS_ANALYST`
Schema: `ANALYTICS`

### DEPARTMENT
Stores the assembly departments on the production floor.

| Column | Type | Description |
|---|---|---|
| dept_id | VARCHAR(10) | Abbreviated department identifier (e.g. `FRM`, `WHL`, `FQC`) |
| description | VARCHAR(100) | Full department name (e.g. Frame, Wheel Assembly, Drivetrain) |

### EMPLOYEE
Stores employee records and their departmental assignments.

| Column | Type | Description |
|---|---|---|
| employee_id | VARCHAR(20) | Unique employee identifier |
| first_name | VARCHAR(50) | First name |
| last_name | VARCHAR(50) | Last name |
| email | VARCHAR(100) | Unique work email |
| gender | VARCHAR(10) | Gender |
| birthday | DATE | Date of birth (used to calculate current age) |
| department_id | VARCHAR(10) | Foreign key to DEPARTMENT |

### TASK
Defines each step in the bike assembly process and its sequencing dependencies.

| Column | Type | Description |
|---|---|---|
| task_id | VARCHAR(10) | Unique task identifier (e.g. `T1`, `T2`) |
| description | VARCHAR(500) | Task name (e.g. Frame Assembly, Fork Installation) |
| precedence | VARCHAR(500) | Which task(s) must be completed before this one |

### TASK_LOG
The core operational table. Every time an employee completes a task on a bike unit, a record is written here.

| Column | Type | Description |
|---|---|---|
| bike_unit_id | VARCHAR(20) | Unique identifier for the bike being assembled (e.g. `BU-2023-000001`) |
| task_date | DATE | Date the task was performed |
| start_time | TIME | When the employee started the task |
| scheduled_end_time | TIME | When the task was expected to finish |
| actual_end_time | TIME | When the task actually finished |
| task_id | VARCHAR(10) | Foreign key to TASK |
| employee_id | VARCHAR(20) | Foreign key to EMPLOYEE |

**Derived metrics available in the semantic model:**
- `TASK_DURATION` — actual time spent on a task in minutes
- `SCHEDULE_VARIANCE_MIN` — how many minutes early (negative) or late (positive) a task finished
- `ON_TIME_RATE` — percentage of tasks completed on or before schedule
- `AVG_DELAY_LATE_ONLY` — average delay in minutes for tasks that ran over
- `BIKE_CYCLE_TIME` — total wall-clock time from first task to last task for a single bike
- `DAILY_BIKE_OUTPUT` — number of bikes completed per day
- `MAX_OVER_RUN_BY_TASK` — worst-case delay per task type
- `TASK_DURATION_STDEV` — standard deviation of task durations (consistency measure)

---

## The GenAI App

The Streamlit in Snowflake app (`bike_operations_analyst_app`) provides a chat interface where operations managers can ask questions about the assembly data in plain English.

**How it works:**

1. The user types a question in the chat input
2. The question is sent to **Cortex Analyst**, which uses the semantic model to generate a SQL query
3. The SQL is executed against the Snowflake tables
4. The results are passed to **`SNOWFLAKE.CORTEX.COMPLETE`** (Claude), which generates a concise natural language answer
5. The answer, the generated SQL, and the raw results are all surfaced in the UI

The app maintains full conversation history so follow-up questions are answered in context.

---

## Sample Questions

Here are some questions you can ask the app:

**Throughput & Output**
- How many bikes were completed last month?
- What is our average daily bike output?
- Which day had the highest bike output this year?

**Schedule & Delays**
- Which task has the worst on-time rate?
- What is the average delay for tasks that run over schedule?
- Which department has the highest schedule variance?

**Task Performance**
- What is the average duration for each assembly task?
- Which task takes the longest to complete on average?
- Which task has the most inconsistent completion times?

**Employee & Department Insights**
- Which department has the most employees?
- Who are the top 5 employees by number of tasks completed?
- Which department completes tasks the fastest on average?

**Cycle Time**
- What is the average cycle time to assemble a bike?
- What is the longest bike cycle time on record?

---

## Setup

1. Run `DDL.sql` in your Snowflake account to create the database, schema, and tables
2. Upload your CSV data files to the `csv_stage` internal stage
3. Load data using the `COPY INTO` statements at the bottom of `DDL.sql`
4. Create a Semantic View in Snowflake using `semantic_model.yaml`
5. Deploy `bike_operations_analyst_app` as a Streamlit in Snowflake app under `SNOWFLAKE_OPERATIONS_ANALYST.ANALYTICS`
