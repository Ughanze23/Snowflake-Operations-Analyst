-- DDL for Snowflake Operations Analyst Database

-- Create database
CREATE OR REPLACE DATABASE SNOWFLAKE_OPERATIONS_ANALYST;

-- Use the database
USE DATABASE SNOWFLAKE_OPERATIONS_ANALYST;

-- Create schema
CREATE OR REPLACE SCHEMA ANALYTICS;

-- Use the schema
USE SCHEMA ANALYTICS;

-- Create file format for CSV files
CREATE OR REPLACE FILE FORMAT csv_format
TYPE = CSV
FIELD_DELIMITER = ','
SKIP_HEADER = 1
NULL_IF = ('NULL', 'null')
EMPTY_AS_NULL = TRUE;

-- Create internal stage for CSV data loading
CREATE OR REPLACE STAGE csv_stage
FILE_FORMAT = csv_format;

-- Create DEPARTMENT table
CREATE OR REPLACE TABLE DEPARTMENT (
    dept_id VARCHAR(10) PRIMARY KEY,
    description VARCHAR(100) NOT NULL
);

-- Create EMPLOYEE table
CREATE OR REPLACE TABLE EMPLOYEE (
    employee_id VARCHAR(20) PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    gender VARCHAR(10),
    birthday DATE,
    department_id VARCHAR(10),
    FOREIGN KEY (department_id) REFERENCES DEPARTMENT(dept_id)
);

-- Create TASK table
CREATE OR REPLACE TABLE TASK (
    task_id VARCHAR(10) PRIMARY KEY,
    description VARCHAR(500) NOT NULL,
    precedence VARCHAR(500)
);

-- Create TASK_LOG table
CREATE OR REPLACE TABLE TASK_LOG (
    task_date DATE NOT NULL,
    start_time TIME NOT NULL,
    scheduled_end_time TIME NOT NULL,
    actual_end_time TIME,
    task_id VARCHAR(10) NOT NULL,
    employee_id VARCHAR(20) NOT NULL,
    bike_unit_id VARCHAR(20) PRIMARY KEY,
    FOREIGN KEY (task_id) REFERENCES TASK(task_id),
    FOREIGN KEY (employee_id) REFERENCES EMPLOYEE(employee_id)
);

-- To load data: Upload CSV files to the internal stage using SnowSQL or Snowflake UI, then run:
-- COPY INTO DEPARTMENT FROM @csv_stage/department.csv;
-- COPY INTO EMPLOYEE FROM @csv_stage/employee.csv;
-- COPY INTO TASK FROM @csv_stage/task.csv;
-- COPY INTO TASK_LOG FROM @csv_stage/task_log.csv;


