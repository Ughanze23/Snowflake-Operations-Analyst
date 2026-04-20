-- DDL for Snowflake Operations Analyst Database

-- Create database
CREATE OR REPLACE DATABASE SNOWFLAKE_OPERATIONS_ANALYST;

-- Use the database
USE DATABASE SNOWFLAKE_OPERATIONS_ANALYST;

-- Create schema
CREATE OR REPLACE SCHEMA ANALYTICS;

-- Use the schema
USE SCHEMA ANALYTICS;

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

