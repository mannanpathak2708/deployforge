-- V1__create_tasks_table.sql
-- Initial schema for DeployForge task management platform

CREATE TABLE tasks (
    id           BIGSERIAL PRIMARY KEY,
    title        VARCHAR(200)  NOT NULL,
    description  VARCHAR(2000),
    status       VARCHAR(20)   NOT NULL DEFAULT 'TODO',
    priority     VARCHAR(10)   NOT NULL DEFAULT 'MEDIUM',
    assigned_to  VARCHAR(100),
    created_at   TIMESTAMP     NOT NULL,
    updated_at   TIMESTAMP     NOT NULL,
    CONSTRAINT chk_status   CHECK (status   IN ('TODO','IN_PROGRESS','IN_REVIEW','DONE','ARCHIVED')),
    CONSTRAINT chk_priority CHECK (priority IN ('LOW','MEDIUM','HIGH','CRITICAL'))
);

CREATE INDEX idx_tasks_status      ON tasks(status);
CREATE INDEX idx_tasks_assigned_to ON tasks(assigned_to);
