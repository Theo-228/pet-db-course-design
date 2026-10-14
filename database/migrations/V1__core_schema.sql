CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA petos;

CREATE TABLE petos.workspace (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    created_at timestamptz NOT NULL DEFAULT now(),
    archived_at timestamptz,
    CONSTRAINT workspace_archive_time CHECK (archived_at IS NULL OR archived_at >= created_at)
);

CREATE TABLE petos.space (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL REFERENCES petos.workspace(id) ON DELETE RESTRICT,
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT space_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT space_name_per_workspace_unique UNIQUE (workspace_id, name)
);

CREATE TABLE petos.pet (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL REFERENCES petos.workspace(id) ON DELETE RESTRICT,
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    species text NOT NULL CHECK (length(btrim(species)) BETWEEN 1 AND 80),
    breed text,
    sex text NOT NULL DEFAULT 'UNKNOWN' CHECK (sex IN ('FEMALE', 'MALE', 'UNKNOWN')),
    birth_date date,
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'OBSERVATION', 'RETIRED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    retired_at timestamptz,
    CONSTRAINT pet_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT pet_retirement_time CHECK (retired_at IS NULL OR retired_at >= created_at),
    CONSTRAINT pet_retirement_status CHECK ((status = 'RETIRED') = (retired_at IS NOT NULL))
);

CREATE TABLE petos.device (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL REFERENCES petos.workspace(id) ON DELETE RESTRICT,
    space_id bigint,
    serial_number text NOT NULL UNIQUE CHECK (length(btrim(serial_number)) BETWEEN 1 AND 120),
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    kind text NOT NULL CHECK (kind IN ('COLLAR', 'SCALE', 'FEEDER', 'WATERER', 'ENVIRONMENT')),
    sharing_policy text NOT NULL CHECK (sharing_policy IN ('DEDICATED', 'SHARED')),
    status text NOT NULL DEFAULT 'OFFLINE' CHECK (status IN ('ONLINE', 'OFFLINE', 'RETIRED')),
    last_seen_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT device_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT device_policy_reference_unique UNIQUE (workspace_id, id, sharing_policy),
    CONSTRAINT device_space_same_workspace FOREIGN KEY (workspace_id, space_id)
        REFERENCES petos.space(workspace_id, id) ON DELETE RESTRICT
);

CREATE TABLE petos.device_pet_binding (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL,
    device_id bigint NOT NULL,
    pet_id bigint NOT NULL,
    sharing_policy text NOT NULL CHECK (sharing_policy IN ('DEDICATED', 'SHARED')),
    bound_at timestamptz NOT NULL,
    unbound_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT binding_interval CHECK (unbound_at IS NULL OR unbound_at > bound_at),
    CONSTRAINT binding_device_policy_fk FOREIGN KEY (workspace_id, device_id, sharing_policy)
        REFERENCES petos.device(workspace_id, id, sharing_policy) ON DELETE RESTRICT,
    CONSTRAINT binding_pet_fk FOREIGN KEY (workspace_id, pet_id)
        REFERENCES petos.pet(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT binding_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT binding_no_duplicate_pet EXCLUDE USING gist (
        workspace_id WITH =,
        device_id WITH =,
        pet_id WITH =,
        tstzrange(bound_at, COALESCE(unbound_at, 'infinity'::timestamptz), '[)') WITH &&
    ),
    CONSTRAINT binding_dedicated_one_pet EXCLUDE USING gist (
        workspace_id WITH =,
        device_id WITH =,
        tstzrange(bound_at, COALESCE(unbound_at, 'infinity'::timestamptz), '[)') WITH &&
    ) WHERE (sharing_policy = 'DEDICATED')
);

CREATE INDEX binding_pet_period_idx ON petos.device_pet_binding (workspace_id, pet_id, bound_at DESC);

CREATE TABLE petos.metric_type (
    code text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_]*$'),
    label text NOT NULL CHECK (length(btrim(label)) > 0),
    unit text NOT NULL CHECK (length(btrim(unit)) > 0),
    scope text NOT NULL CHECK (scope IN ('PET', 'DEVICE', 'SPACE')),
    minimum numeric(18,4),
    maximum numeric(18,4),
    CONSTRAINT metric_bounds CHECK (minimum IS NULL OR maximum IS NULL OR minimum <= maximum)
);

CREATE TABLE petos.device_metric_capability (
    device_kind text NOT NULL CHECK (device_kind IN ('COLLAR', 'SCALE', 'FEEDER', 'WATERER', 'ENVIRONMENT')),
    metric_code text NOT NULL REFERENCES petos.metric_type(code) ON DELETE RESTRICT,
    PRIMARY KEY (device_kind, metric_code)
);

CREATE TABLE petos.measurement (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL REFERENCES petos.workspace(id) ON DELETE RESTRICT,
    device_id bigint,
    space_id bigint,
    source_kind text NOT NULL CHECK (source_kind IN ('DEVICE', 'MANUAL')),
    source_event_id text,
    metric_code text NOT NULL REFERENCES petos.metric_type(code) ON DELETE RESTRICT,
    value numeric(18,4) NOT NULL,
    measured_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT measurement_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT measurement_device_fk FOREIGN KEY (workspace_id, device_id)
        REFERENCES petos.device(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT measurement_space_fk FOREIGN KEY (workspace_id, space_id)
        REFERENCES petos.space(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT measurement_source_shape CHECK (
        (source_kind = 'DEVICE' AND device_id IS NOT NULL
            AND source_event_id IS NOT NULL AND length(btrim(source_event_id)) > 0)
        OR (source_kind = 'MANUAL' AND device_id IS NULL AND source_event_id IS NULL)
    ),
    CONSTRAINT measurement_device_event_unique UNIQUE (workspace_id, device_id, source_event_id)
);

CREATE INDEX measurement_metric_time_idx ON petos.measurement (workspace_id, metric_code, measured_at DESC);
CREATE INDEX measurement_device_time_idx ON petos.measurement (workspace_id, device_id, measured_at DESC)
    WHERE device_id IS NOT NULL;

CREATE FUNCTION petos.check_measurement() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    selected_metric petos.metric_type%ROWTYPE;
    selected_device_kind text;
BEGIN
    SELECT * INTO STRICT selected_metric FROM petos.metric_type WHERE code = NEW.metric_code;
    IF (selected_metric.minimum IS NOT NULL AND NEW.value < selected_metric.minimum)
       OR (selected_metric.maximum IS NOT NULL AND NEW.value > selected_metric.maximum) THEN
        RAISE EXCEPTION 'measurement % outside allowed range for %', NEW.value, NEW.metric_code
            USING ERRCODE = '23514';
    END IF;

    IF NEW.source_kind = 'MANUAL' AND selected_metric.scope <> 'PET' THEN
        RAISE EXCEPTION 'manual measurement requires a pet metric'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.source_kind = 'DEVICE' THEN
        SELECT kind INTO STRICT selected_device_kind
        FROM petos.device WHERE workspace_id = NEW.workspace_id AND id = NEW.device_id;
        IF NOT EXISTS (
            SELECT 1 FROM petos.device_metric_capability
            WHERE device_kind = selected_device_kind AND metric_code = NEW.metric_code
        ) THEN
            RAISE EXCEPTION 'device kind % cannot report metric %', selected_device_kind, NEW.metric_code
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER measurement_check_before_insert
BEFORE INSERT ON petos.measurement
FOR EACH ROW EXECUTE FUNCTION petos.check_measurement();

CREATE FUNCTION petos.reject_measurement_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'raw measurements are immutable; append an attribution revision instead'
        USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER measurement_no_update_or_delete
BEFORE UPDATE OR DELETE ON petos.measurement
FOR EACH ROW EXECUTE FUNCTION petos.reject_measurement_change();

CREATE TABLE petos.measurement_attribution (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL,
    measurement_id bigint NOT NULL,
    pet_id bigint,
    method text NOT NULL CHECK (method IN ('UNKNOWN', 'BINDING', 'IDENTIFIED', 'MANUAL')),
    confidence numeric(5,4),
    reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 1 AND 500),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT attribution_measurement_fk FOREIGN KEY (workspace_id, measurement_id)
        REFERENCES petos.measurement(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT attribution_pet_fk FOREIGN KEY (workspace_id, pet_id)
        REFERENCES petos.pet(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT attribution_shape CHECK (
        (method = 'UNKNOWN' AND pet_id IS NULL AND confidence IS NULL)
        OR (method <> 'UNKNOWN' AND pet_id IS NOT NULL)
    ),
    CONSTRAINT attribution_confidence CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1)
);

CREATE INDEX attribution_latest_idx ON petos.measurement_attribution
    (workspace_id, measurement_id, id DESC);
CREATE INDEX attribution_pet_idx ON petos.measurement_attribution (workspace_id, pet_id, id DESC)
    WHERE pet_id IS NOT NULL;

CREATE FUNCTION petos.check_attribution() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    source_measurement petos.measurement%ROWTYPE;
    selected_scope text;
    selected_policy text;
BEGIN
    SELECT * INTO STRICT source_measurement FROM petos.measurement
        WHERE workspace_id = NEW.workspace_id AND id = NEW.measurement_id;
    SELECT scope INTO STRICT selected_scope FROM petos.metric_type
        WHERE code = source_measurement.metric_code;
    IF selected_scope <> 'PET' THEN
        RAISE EXCEPTION 'only pet metrics can be attributed to a pet'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.method = 'BINDING' THEN
        IF source_measurement.device_id IS NULL THEN
            RAISE EXCEPTION 'binding attribution requires a device'
                USING ERRCODE = '23514';
        END IF;
        SELECT sharing_policy INTO STRICT selected_policy FROM petos.device
            WHERE workspace_id = NEW.workspace_id AND id = source_measurement.device_id;
        IF selected_policy <> 'DEDICATED' THEN
            RAISE EXCEPTION 'shared device binding alone does not identify a pet'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.method IN ('BINDING', 'IDENTIFIED') AND NOT EXISTS (
        SELECT 1 FROM petos.device_pet_binding b
        WHERE b.workspace_id = NEW.workspace_id
          AND b.device_id = source_measurement.device_id
          AND b.pet_id = NEW.pet_id
          AND b.bound_at <= source_measurement.measured_at
          AND (b.unbound_at IS NULL OR source_measurement.measured_at < b.unbound_at)
    ) THEN
        RAISE EXCEPTION 'pet is not associated with this device at measurement time'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER attribution_check_before_insert
BEFORE INSERT ON petos.measurement_attribution
FOR EACH ROW EXECUTE FUNCTION petos.check_attribution();

CREATE FUNCTION petos.reject_attribution_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'attribution revisions are immutable; insert a new revision'
        USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER attribution_no_update_or_delete
BEFORE UPDATE OR DELETE ON petos.measurement_attribution
FOR EACH ROW EXECUTE FUNCTION petos.reject_attribution_change();

CREATE TABLE petos.health_record (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL,
    pet_id bigint NOT NULL,
    kind text NOT NULL CHECK (kind IN ('OBSERVATION', 'VACCINATION', 'TREATMENT', 'VET_VISIT')),
    occurred_at timestamptz NOT NULL,
    note text NOT NULL CHECK (length(btrim(note)) BETWEEN 1 AND 2000),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT health_record_pet_fk FOREIGN KEY (workspace_id, pet_id)
        REFERENCES petos.pet(workspace_id, id) ON DELETE RESTRICT
);

CREATE INDEX health_record_pet_time_idx ON petos.health_record (workspace_id, pet_id, occurred_at DESC);

CREATE TABLE petos.automation_rule (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL REFERENCES petos.workspace(id) ON DELETE RESTRICT,
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    enabled boolean NOT NULL DEFAULT true,
    metric_code text NOT NULL REFERENCES petos.metric_type(code) ON DELETE RESTRICT,
    comparator text NOT NULL CHECK (comparator IN ('GT', 'GTE', 'LT', 'LTE')),
    threshold numeric(18,4) NOT NULL,
    source_device_id bigint,
    pet_id bigint,
    action_kind text NOT NULL CHECK (action_kind IN ('ALERT', 'DEVICE_COMMAND')),
    target_device_id bigint,
    action_payload jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(action_payload) = 'object'),
    severity text NOT NULL DEFAULT 'INFO' CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL')),
    cooldown_seconds integer NOT NULL DEFAULT 0 CHECK (cooldown_seconds BETWEEN 0 AND 86400),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT rule_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT rule_name_per_workspace_unique UNIQUE (workspace_id, name),
    CONSTRAINT rule_source_device_fk FOREIGN KEY (workspace_id, source_device_id)
        REFERENCES petos.device(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT rule_target_device_fk FOREIGN KEY (workspace_id, target_device_id)
        REFERENCES petos.device(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT rule_pet_fk FOREIGN KEY (workspace_id, pet_id)
        REFERENCES petos.pet(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT rule_action_shape CHECK (
        (action_kind = 'ALERT' AND target_device_id IS NULL)
        OR (action_kind = 'DEVICE_COMMAND' AND target_device_id IS NOT NULL)
    )
);

CREATE INDEX rule_enabled_metric_idx ON petos.automation_rule (workspace_id, metric_code)
    WHERE enabled;

CREATE TABLE petos.automation_execution (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL,
    rule_id bigint NOT NULL,
    measurement_id bigint NOT NULL,
    action_kind text NOT NULL CHECK (action_kind IN ('ALERT', 'DEVICE_COMMAND')),
    status text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'SKIPPED')),
    triggered_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    error_message text,
    CONSTRAINT execution_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT execution_once_per_rule_measurement UNIQUE (rule_id, measurement_id),
    CONSTRAINT execution_rule_fk FOREIGN KEY (workspace_id, rule_id)
        REFERENCES petos.automation_rule(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT execution_measurement_fk FOREIGN KEY (workspace_id, measurement_id)
        REFERENCES petos.measurement(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT execution_completion_shape CHECK (
        (status = 'PENDING' AND completed_at IS NULL)
        OR (status <> 'PENDING' AND completed_at IS NOT NULL AND completed_at >= triggered_at)
    )
);

CREATE INDEX execution_rule_time_idx ON petos.automation_execution (workspace_id, rule_id, triggered_at DESC);

CREATE TABLE petos.device_command (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL,
    device_id bigint NOT NULL,
    automation_execution_id bigint,
    command_type text NOT NULL CHECK (command_type ~ '^[A-Z][A-Z0-9_]*$'),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload) = 'object'),
    status text NOT NULL DEFAULT 'REQUESTED' CHECK (status IN ('REQUESTED', 'APPLIED', 'FAILED', 'CANCELLED')),
    idempotency_key text NOT NULL CHECK (length(btrim(idempotency_key)) BETWEEN 1 AND 120),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    CONSTRAINT command_workspace_id_id_unique UNIQUE (workspace_id, id),
    CONSTRAINT command_idempotent_per_device UNIQUE (device_id, idempotency_key),
    CONSTRAINT command_execution_unique UNIQUE (automation_execution_id),
    CONSTRAINT command_device_fk FOREIGN KEY (workspace_id, device_id)
        REFERENCES petos.device(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT command_execution_fk FOREIGN KEY (workspace_id, automation_execution_id)
        REFERENCES petos.automation_execution(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT command_completion_shape CHECK (
        (status = 'REQUESTED' AND completed_at IS NULL)
        OR (status <> 'REQUESTED' AND completed_at IS NOT NULL AND completed_at >= requested_at)
    )
);

CREATE INDEX command_device_time_idx ON petos.device_command (workspace_id, device_id, requested_at DESC);

CREATE TABLE petos.alert_event (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    workspace_id bigint NOT NULL REFERENCES petos.workspace(id) ON DELETE RESTRICT,
    automation_execution_id bigint,
    pet_id bigint,
    device_id bigint,
    severity text NOT NULL CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL')),
    title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
    details text,
    status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RESOLVED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CONSTRAINT alert_execution_unique UNIQUE (automation_execution_id),
    CONSTRAINT alert_execution_fk FOREIGN KEY (workspace_id, automation_execution_id)
        REFERENCES petos.automation_execution(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT alert_pet_fk FOREIGN KEY (workspace_id, pet_id)
        REFERENCES petos.pet(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT alert_device_fk FOREIGN KEY (workspace_id, device_id)
        REFERENCES petos.device(workspace_id, id) ON DELETE RESTRICT,
    CONSTRAINT alert_resolution_shape CHECK (
        (status = 'OPEN' AND resolved_at IS NULL)
        OR (status = 'RESOLVED' AND resolved_at IS NOT NULL AND resolved_at >= created_at)
    )
);

CREATE INDEX alert_open_time_idx ON petos.alert_event (workspace_id, created_at DESC)
    WHERE status = 'OPEN';

COMMENT ON SCHEMA petos IS 'PetOS shared data model for home and cafe workspaces';
COMMENT ON TABLE petos.measurement IS 'Immutable raw observation; identity is tracked separately';
COMMENT ON TABLE petos.measurement_attribution IS 'Append-only attribution revisions ordered by id';
COMMENT ON TABLE petos.automation_execution IS 'Idempotent rule action attempt for one raw measurement';
