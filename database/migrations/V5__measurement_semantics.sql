ALTER TABLE petos.metric_type
    ADD COLUMN requires_period boolean NOT NULL DEFAULT false;

UPDATE petos.metric_type SET requires_period = true WHERE code = 'activity_minutes';

ALTER TABLE petos.measurement
    ADD COLUMN period_started_at timestamptz,
    ADD CONSTRAINT measurement_period_order CHECK (
        period_started_at IS NULL OR period_started_at < measured_at
    );

CREATE FUNCTION petos.check_measurement_semantics() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    selected_metric petos.metric_type%ROWTYPE;
BEGIN
    SELECT * INTO STRICT selected_metric FROM petos.metric_type
        WHERE code = NEW.metric_code;
    IF selected_metric.requires_period IS DISTINCT FROM (NEW.period_started_at IS NOT NULL) THEN
        RAISE EXCEPTION 'metric % period requirement does not match measurement', NEW.metric_code
            USING ERRCODE = '23514';
    END IF;
    IF selected_metric.scope = 'SPACE' AND NEW.space_id IS NULL THEN
        RAISE EXCEPTION 'space metric requires a space_id'
            USING ERRCODE = '23514';
    END IF;
    IF selected_metric.requires_period AND NEW.value >
        extract(epoch FROM (NEW.measured_at - NEW.period_started_at)) / 60 THEN
        RAISE EXCEPTION 'activity duration exceeds the observation period'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER measurement_semantics_before_insert
BEFORE INSERT ON petos.measurement
FOR EACH ROW EXECUTE FUNCTION petos.check_measurement_semantics();

CREATE FUNCTION petos.check_manual_attribution_at_commit() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.source_kind = 'MANUAL' AND NOT EXISTS (
        SELECT 1 FROM petos.measurement_attribution a
        WHERE a.workspace_id = NEW.workspace_id
          AND a.measurement_id = NEW.id
          AND a.method = 'MANUAL'
          AND a.pet_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'manual measurement needs a pet attribution in the same transaction'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER manual_attribution_at_commit
AFTER INSERT ON petos.measurement
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION petos.check_manual_attribution_at_commit();
