ALTER TABLE petos.automation_execution
    ADD COLUMN rule_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE petos.automation_rule
    ADD CONSTRAINT rule_command_payload CHECK (
        action_kind <> 'DEVICE_COMMAND'
        OR (
            action_payload ? 'command_type'
            AND jsonb_typeof(action_payload -> 'command_type') = 'string'
            AND action_payload ->> 'command_type' ~ '^[A-Z][A-Z0-9_]*$'
        )
    );

CREATE FUNCTION petos.check_rule() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    selected_metric petos.metric_type%ROWTYPE;
BEGIN
    SELECT * INTO STRICT selected_metric FROM petos.metric_type WHERE code = NEW.metric_code;
    IF NEW.pet_id IS NOT NULL AND selected_metric.scope <> 'PET' THEN
        RAISE EXCEPTION 'pet-specific rule requires a pet metric'
            USING ERRCODE = '23514';
    END IF;
    IF (selected_metric.minimum IS NOT NULL AND NEW.threshold < selected_metric.minimum)
       OR (selected_metric.maximum IS NOT NULL AND NEW.threshold > selected_metric.maximum) THEN
        RAISE EXCEPTION 'rule threshold outside metric range'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER rule_check_before_write
BEFORE INSERT OR UPDATE ON petos.automation_rule
FOR EACH ROW EXECUTE FUNCTION petos.check_rule();

CREATE FUNCTION petos.check_execution() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    selected_rule petos.automation_rule%ROWTYPE;
    selected_measurement petos.measurement%ROWTYPE;
    attributed_pet_id bigint;
    attribution_revision_id bigint;
    crossed boolean;
BEGIN
    SELECT * INTO STRICT selected_rule FROM petos.automation_rule
        WHERE workspace_id = NEW.workspace_id AND id = NEW.rule_id FOR UPDATE;
    SELECT * INTO STRICT selected_measurement FROM petos.measurement
        WHERE workspace_id = NEW.workspace_id AND id = NEW.measurement_id;
    SELECT v.pet_id, v.attribution_revision_id
        INTO attributed_pet_id, attribution_revision_id
    FROM petos.v_measurement_current v
    WHERE v.workspace_id = NEW.workspace_id AND v.id = NEW.measurement_id;

    IF NOT selected_rule.enabled
       OR selected_rule.metric_code <> selected_measurement.metric_code
       OR selected_rule.action_kind <> NEW.action_kind
       OR (selected_rule.source_device_id IS NOT NULL
           AND selected_rule.source_device_id IS DISTINCT FROM selected_measurement.device_id)
       OR (selected_rule.pet_id IS NOT NULL
           AND selected_rule.pet_id IS DISTINCT FROM attributed_pet_id) THEN
        RAISE EXCEPTION 'measurement does not match the enabled rule'
            USING ERRCODE = '23514';
    END IF;

    crossed := CASE selected_rule.comparator
        WHEN 'GT' THEN selected_measurement.value > selected_rule.threshold
        WHEN 'GTE' THEN selected_measurement.value >= selected_rule.threshold
        WHEN 'LT' THEN selected_measurement.value < selected_rule.threshold
        WHEN 'LTE' THEN selected_measurement.value <= selected_rule.threshold
        ELSE false
    END;
    IF NOT crossed THEN
        RAISE EXCEPTION 'measurement did not cross the rule threshold'
            USING ERRCODE = '23514';
    END IF;

    IF selected_rule.cooldown_seconds > 0 AND EXISTS (
        SELECT 1 FROM petos.automation_execution e
        WHERE e.rule_id = NEW.rule_id
          AND e.triggered_at > NEW.triggered_at
              - make_interval(secs => selected_rule.cooldown_seconds)
          AND e.triggered_at <= NEW.triggered_at
          AND e.status <> 'SKIPPED'
    ) THEN
        RAISE EXCEPTION 'rule is in cooldown period'
            USING ERRCODE = '23514';
    END IF;

    NEW.rule_snapshot := jsonb_build_object(
        'name', selected_rule.name,
        'metric_code', selected_rule.metric_code,
        'comparator', selected_rule.comparator,
        'threshold', selected_rule.threshold,
        'action_kind', selected_rule.action_kind,
        'target_device_id', selected_rule.target_device_id,
        'source_device_id', selected_measurement.device_id,
        'attributed_pet_id', attributed_pet_id,
        'attribution_revision_id', attribution_revision_id,
        'severity', selected_rule.severity,
        'action_payload', selected_rule.action_payload
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER execution_check_before_insert
BEFORE INSERT ON petos.automation_execution
FOR EACH ROW EXECUTE FUNCTION petos.check_execution();

CREATE FUNCTION petos.reject_execution_identity_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.workspace_id, NEW.rule_id, NEW.measurement_id, NEW.action_kind,
        NEW.rule_snapshot, NEW.triggered_at)
        IS DISTINCT FROM
       (OLD.workspace_id, OLD.rule_id, OLD.measurement_id, OLD.action_kind,
        OLD.rule_snapshot, OLD.triggered_at) THEN
        RAISE EXCEPTION 'execution identity and rule snapshot are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.status <> 'PENDING' AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'completed execution status cannot be changed'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER execution_identity_before_update
BEFORE UPDATE ON petos.automation_execution
FOR EACH ROW EXECUTE FUNCTION petos.reject_execution_identity_change();

CREATE FUNCTION petos.reject_execution_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'automation execution history cannot be deleted'
        USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER execution_no_delete
BEFORE DELETE ON petos.automation_execution
FOR EACH ROW EXECUTE FUNCTION petos.reject_execution_delete();

CREATE FUNCTION petos.check_action_link() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    selected_execution petos.automation_execution%ROWTYPE;
BEGIN
    IF NEW.automation_execution_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT * INTO STRICT selected_execution FROM petos.automation_execution
        WHERE workspace_id = NEW.workspace_id AND id = NEW.automation_execution_id;
    IF TG_TABLE_NAME = 'alert_event' THEN
        IF selected_execution.action_kind <> 'ALERT'
           OR NEW.pet_id IS DISTINCT FROM
               (selected_execution.rule_snapshot ->> 'attributed_pet_id')::bigint
           OR NEW.severity IS DISTINCT FROM
               (selected_execution.rule_snapshot ->> 'severity') THEN
            RAISE EXCEPTION 'alert does not match its automation execution'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF selected_execution.action_kind <> 'DEVICE_COMMAND'
           OR NEW.device_id IS DISTINCT FROM
               (selected_execution.rule_snapshot ->> 'target_device_id')::bigint
           OR NEW.command_type IS DISTINCT FROM
               (selected_execution.rule_snapshot #>> '{action_payload,command_type}') THEN
            RAISE EXCEPTION 'device command does not match its automation execution'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER alert_link_before_write
BEFORE INSERT OR UPDATE OF automation_execution_id, pet_id ON petos.alert_event
FOR EACH ROW EXECUTE FUNCTION petos.check_action_link();

CREATE TRIGGER command_link_before_write
BEFORE INSERT OR UPDATE OF automation_execution_id, device_id, command_type ON petos.device_command
FOR EACH ROW EXECUTE FUNCTION petos.check_action_link();

CREATE FUNCTION petos.guard_action_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'action history cannot be deleted'
            USING ERRCODE = '55000';
    END IF;
    IF TG_TABLE_NAME = 'alert_event' THEN
        IF (NEW.id, NEW.workspace_id, NEW.automation_execution_id, NEW.pet_id,
            NEW.device_id, NEW.severity, NEW.title, NEW.details, NEW.created_at)
           IS DISTINCT FROM
           (OLD.id, OLD.workspace_id, OLD.automation_execution_id, OLD.pet_id,
            OLD.device_id, OLD.severity, OLD.title, OLD.details, OLD.created_at)
           OR (OLD.status = 'RESOLVED' AND NEW.status <> 'RESOLVED') THEN
            RAISE EXCEPTION 'alert identity is immutable and resolution is final'
                USING ERRCODE = '55000';
        END IF;
    ELSE
        IF (NEW.id, NEW.workspace_id, NEW.automation_execution_id, NEW.device_id,
            NEW.command_type, NEW.payload, NEW.idempotency_key, NEW.requested_at)
           IS DISTINCT FROM
           (OLD.id, OLD.workspace_id, OLD.automation_execution_id, OLD.device_id,
            OLD.command_type, OLD.payload, OLD.idempotency_key, OLD.requested_at)
           OR (OLD.status <> 'REQUESTED' AND NEW.status <> OLD.status) THEN
            RAISE EXCEPTION 'command identity is immutable and completion is final'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER alert_guard_before_change
BEFORE UPDATE OR DELETE ON petos.alert_event
FOR EACH ROW EXECUTE FUNCTION petos.guard_action_change();

CREATE TRIGGER command_guard_before_change
BEFORE UPDATE OR DELETE ON petos.device_command
FOR EACH ROW EXECUTE FUNCTION petos.guard_action_change();

CREATE FUNCTION petos.check_completed_execution() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    current_status text;
BEGIN
    SELECT status INTO current_status FROM petos.automation_execution
        WHERE workspace_id = NEW.workspace_id AND id = NEW.id;
    IF current_status = 'SUCCEEDED' AND NOT EXISTS (
        SELECT 1 FROM petos.alert_event a
        WHERE NEW.action_kind = 'ALERT'
          AND a.workspace_id = NEW.workspace_id
          AND a.automation_execution_id = NEW.id
        UNION ALL
        SELECT 1 FROM petos.device_command c
        WHERE NEW.action_kind = 'DEVICE_COMMAND'
          AND c.workspace_id = NEW.workspace_id
          AND c.automation_execution_id = NEW.id
          AND c.status = 'APPLIED'
    ) THEN
        RAISE EXCEPTION 'successful execution has no matching action record'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER execution_action_at_commit
AFTER INSERT OR UPDATE ON petos.automation_execution
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION petos.check_completed_execution();

CREATE FUNCTION petos.guard_binding_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'binding history cannot be deleted'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.unbound_at IS NOT NULL
       OR NEW.unbound_at IS NULL
       OR (NEW.id, NEW.workspace_id, NEW.device_id, NEW.pet_id,
           NEW.sharing_policy, NEW.bound_at, NEW.created_at)
          IS DISTINCT FROM
          (OLD.id, OLD.workspace_id, OLD.device_id, OLD.pet_id,
           OLD.sharing_policy, OLD.bound_at, OLD.created_at) THEN
        RAISE EXCEPTION 'only an open binding can be closed'
            USING ERRCODE = '55000';
    END IF;
    IF EXISTS (
        SELECT 1 FROM petos.measurement_attribution a
        JOIN petos.measurement m
          ON m.workspace_id = a.workspace_id AND m.id = a.measurement_id
        WHERE a.workspace_id = OLD.workspace_id
          AND a.pet_id = OLD.pet_id
          AND a.method IN ('BINDING', 'IDENTIFIED')
          AND m.device_id = OLD.device_id
          AND m.measured_at >= NEW.unbound_at
          AND m.measured_at >= OLD.bound_at
    ) THEN
        RAISE EXCEPTION 'binding cannot end before a supported attribution'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER binding_guard_before_change
BEFORE UPDATE OR DELETE ON petos.device_pet_binding
FOR EACH ROW EXECUTE FUNCTION petos.guard_binding_change();
