CREATE TABLE petos.automation_dispatch (
    workspace_id bigint NOT NULL,
    measurement_id bigint NOT NULL,
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'COMPLETED')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    PRIMARY KEY (workspace_id, measurement_id),
    CONSTRAINT dispatch_measurement_fk FOREIGN KEY (workspace_id, measurement_id)
        REFERENCES petos.measurement(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT dispatch_completion_shape CHECK (
        (status = 'PENDING' AND processed_at IS NULL)
        OR (status = 'COMPLETED' AND processed_at IS NOT NULL)
    )
);

CREATE INDEX automation_dispatch_pending_idx
    ON petos.automation_dispatch (created_at, measurement_id)
    WHERE status = 'PENDING';

CREATE FUNCTION petos.enqueue_automation_dispatch() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO petos.automation_dispatch (workspace_id, measurement_id)
    VALUES (NEW.workspace_id, NEW.id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER measurement_enqueue_automation
AFTER INSERT ON petos.measurement
FOR EACH ROW EXECUTE FUNCTION petos.enqueue_automation_dispatch();

COMMENT ON TABLE petos.automation_dispatch IS
    'Durable after-commit automation work; retried by the application after a crash';
