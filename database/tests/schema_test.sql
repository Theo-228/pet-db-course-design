BEGIN;

DO $$
DECLARE
    home_id bigint;
    cafe_id bigint;
    home_space_id bigint;
    cafe_space_id bigint;
    user_id bigint;
    pet_a_id bigint;
    pet_b_id bigint;
    foreign_pet_id bigint;
    scale_id bigint;
    shared_scale_id bigint;
    collar_id bigint;
    weight_id bigint;
    shared_weight_id bigint;
    second_weight_id bigint;
    manual_weight_id bigint;
    rule_id bigint;
    cooldown_rule_id bigint;
    orphan_rule_id bigint;
    execution_id bigint;
    actual_pet_id bigint;
    revision_count integer;
BEGIN
    INSERT INTO petos.workspace (name) VALUES ('test-home') RETURNING id INTO home_id;
    INSERT INTO petos.workspace (name) VALUES ('test-cafe') RETURNING id INTO cafe_id;
    INSERT INTO petos.space (workspace_id, name) VALUES (home_id, 'room') RETURNING id INTO home_space_id;
    INSERT INTO petos.space (workspace_id, name) VALUES (cafe_id, 'room') RETURNING id INTO cafe_space_id;
    INSERT INTO petos.user_account (login_name, password_hash)
        VALUES ('tester@example.org', 'demo-only-hash-placeholder-12345') RETURNING id INTO user_id;
    INSERT INTO petos.workspace_membership (workspace_id, user_id, role)
        VALUES (home_id, user_id, 'OWNER');
    BEGIN
        INSERT INTO petos.user_account (login_name, password_hash)
            VALUES ('TESTER@example.org', 'demo-only-hash-placeholder-12345');
        RAISE EXCEPTION 'case-insensitive duplicate login was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    INSERT INTO petos.pet (workspace_id, name, species)
        VALUES (home_id, 'Mochi', 'cat') RETURNING id INTO pet_a_id;
    INSERT INTO petos.pet (workspace_id, name, species)
        VALUES (home_id, 'Mimi', 'cat') RETURNING id INTO pet_b_id;
    INSERT INTO petos.pet (workspace_id, name, species)
        VALUES (cafe_id, 'Other', 'cat') RETURNING id INTO foreign_pet_id;

    BEGIN
        INSERT INTO petos.device (workspace_id, space_id, serial_number, name, kind, sharing_policy)
            VALUES (home_id, cafe_space_id, 'test-invalid-space', 'wrong room', 'SCALE', 'DEDICATED');
        RAISE EXCEPTION 'cross-workspace space reference was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    INSERT INTO petos.device (workspace_id, space_id, serial_number, name, kind, sharing_policy)
        VALUES (home_id, home_space_id, 'test-scale-1', 'private scale', 'SCALE', 'DEDICATED')
        RETURNING id INTO scale_id;
    INSERT INTO petos.device (workspace_id, space_id, serial_number, name, kind, sharing_policy)
        VALUES (home_id, home_space_id, 'test-scale-2', 'shared scale', 'SCALE', 'SHARED')
        RETURNING id INTO shared_scale_id;
    INSERT INTO petos.device (workspace_id, space_id, serial_number, name, kind, sharing_policy)
        VALUES (home_id, home_space_id, 'test-collar-1', 'collar', 'COLLAR', 'DEDICATED')
        RETURNING id INTO collar_id;

    INSERT INTO petos.device_pet_binding
        (workspace_id, device_id, pet_id, sharing_policy, bound_at, unbound_at)
        VALUES (home_id, scale_id, pet_a_id, 'DEDICATED', '2030-01-01', '2030-02-01');
    BEGIN
        INSERT INTO petos.device_pet_binding
            (workspace_id, device_id, pet_id, sharing_policy, bound_at, unbound_at)
            VALUES (home_id, scale_id, pet_b_id, 'DEDICATED', '2030-01-15', '2030-02-15');
        RAISE EXCEPTION 'overlapping dedicated binding was accepted';
    EXCEPTION WHEN exclusion_violation THEN NULL;
    END;
    INSERT INTO petos.device_pet_binding
        (workspace_id, device_id, pet_id, sharing_policy, bound_at, unbound_at)
        VALUES (home_id, scale_id, pet_b_id, 'DEDICATED', '2030-02-01', NULL);

    INSERT INTO petos.device_pet_binding
        (workspace_id, device_id, pet_id, sharing_policy, bound_at)
        VALUES (home_id, shared_scale_id, pet_a_id, 'SHARED', '2030-01-01');
    INSERT INTO petos.device_pet_binding
        (workspace_id, device_id, pet_id, sharing_policy, bound_at)
        VALUES (home_id, shared_scale_id, pet_b_id, 'SHARED', '2030-01-01');
    INSERT INTO petos.device_pet_binding
        (workspace_id, device_id, pet_id, sharing_policy, bound_at)
        VALUES (home_id, collar_id, pet_a_id, 'DEDICATED', '2030-01-01');
    BEGIN
        INSERT INTO petos.device_pet_binding
            (workspace_id, device_id, pet_id, sharing_policy, bound_at)
            VALUES (home_id, shared_scale_id, foreign_pet_id, 'SHARED', '2030-01-01');
        RAISE EXCEPTION 'cross-workspace pet binding was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    INSERT INTO petos.measurement
        (workspace_id, device_id, space_id, source_kind, source_event_id, metric_code, value, measured_at)
        VALUES (home_id, scale_id, home_space_id, 'DEVICE', 'weight-1', 'weight_kg', 3.8000, '2030-01-10')
        RETURNING id INTO weight_id;
    INSERT INTO petos.measurement_attribution
        (workspace_id, measurement_id, pet_id, method, confidence, reason)
        VALUES (home_id, weight_id, pet_a_id, 'BINDING', 1.0000, 'private scale binding');
    INSERT INTO petos.measurement
        (workspace_id, device_id, source_kind, source_event_id, metric_code,
         value, period_started_at, measured_at)
        VALUES (home_id, collar_id, 'DEVICE', 'activity-1', 'activity_minutes',
                40, '2030-01-10 10:00+08', '2030-01-10 11:00+08');
    BEGIN
        INSERT INTO petos.measurement
            (workspace_id, device_id, source_kind, source_event_id, metric_code,
             value, period_started_at, measured_at)
            VALUES (home_id, collar_id, 'DEVICE', 'activity-too-long', 'activity_minutes',
                    90, '2030-01-10 10:00+08', '2030-01-10 11:00+08');
        RAISE EXCEPTION 'activity duration exceeded the observation period';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    INSERT INTO petos.measurement
        (workspace_id, source_kind, metric_code, value, measured_at)
        VALUES (home_id, 'MANUAL', 'weight_kg', 3.9000, '2030-01-09')
        RETURNING id INTO manual_weight_id;
    INSERT INTO petos.measurement_attribution
        (workspace_id, measurement_id, pet_id, method, reason)
        VALUES (home_id, manual_weight_id, pet_a_id, 'MANUAL', 'hand-entered weight');
    BEGIN
        INSERT INTO petos.measurement
            (workspace_id, source_kind, metric_code, value, measured_at)
            VALUES (home_id, 'MANUAL', 'weight_kg', 3.9500, '2030-01-08');
        SET CONSTRAINTS petos.manual_attribution_at_commit IMMEDIATE;
        RAISE EXCEPTION 'orphan manual measurement was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO petos.measurement
            (workspace_id, device_id, source_kind, source_event_id, metric_code, value, measured_at)
            VALUES (home_id, scale_id, 'DEVICE', 'weight-1', 'weight_kg', 3.8000, '2030-01-10');
        RAISE EXCEPTION 'duplicate device event was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO petos.measurement
            (workspace_id, device_id, source_kind, source_event_id, metric_code, value, measured_at)
            VALUES (home_id, scale_id, 'DEVICE', 'weight-out-of-range', 'weight_kg', 201, '2030-01-10');
        RAISE EXCEPTION 'out-of-range measurement was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO petos.measurement
            (workspace_id, device_id, source_kind, source_event_id, metric_code, value, measured_at)
            VALUES (home_id, scale_id, 'DEVICE', 'wrong-capability', 'activity_minutes', 30, '2030-01-10');
        RAISE EXCEPTION 'wrong metric capability was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE petos.measurement SET value = 4 WHERE id = weight_id;
        RAISE EXCEPTION 'raw measurement update was accepted';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;

    INSERT INTO petos.measurement
        (workspace_id, device_id, source_kind, source_event_id, metric_code, value, measured_at)
        VALUES (home_id, shared_scale_id, 'DEVICE', 'shared-weight-1', 'weight_kg', 4.2000, '2030-01-11')
        RETURNING id INTO shared_weight_id;
    SELECT pet_id INTO actual_pet_id FROM petos.v_measurement_current WHERE id = shared_weight_id;
    IF actual_pet_id IS NOT NULL THEN
        RAISE EXCEPTION 'unknown shared-device identity was assigned';
    END IF;
    BEGIN
        INSERT INTO petos.measurement_attribution
            (workspace_id, measurement_id, pet_id, method, reason)
            VALUES (home_id, shared_weight_id, pet_a_id, 'BINDING', 'invalid inference');
        RAISE EXCEPTION 'shared binding alone identified a pet';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    INSERT INTO petos.measurement_attribution
        (workspace_id, measurement_id, pet_id, method, confidence, reason)
        VALUES (home_id, shared_weight_id, pet_a_id, 'IDENTIFIED', 0.9500, 'simulated RFID match');
    INSERT INTO petos.measurement_attribution
        (workspace_id, measurement_id, pet_id, method, reason)
        VALUES (home_id, shared_weight_id, pet_b_id, 'MANUAL', 'verified correction');
    BEGIN
        UPDATE petos.device_pet_binding SET unbound_at = '2030-01-10'
        WHERE workspace_id = home_id AND device_id = shared_scale_id AND pet_id = pet_a_id;
        RAISE EXCEPTION 'binding closed before an attributed measurement';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    SELECT pet_id INTO actual_pet_id FROM petos.v_measurement_current WHERE id = shared_weight_id;
    SELECT count(*) INTO revision_count FROM petos.measurement_attribution
        WHERE measurement_id = shared_weight_id;
    IF actual_pet_id <> pet_b_id OR revision_count <> 2 THEN
        RAISE EXCEPTION 'attribution revision history is incorrect';
    END IF;
    BEGIN
        INSERT INTO petos.measurement_attribution
            (workspace_id, measurement_id, pet_id, method, reason)
            VALUES (home_id, shared_weight_id, foreign_pet_id, 'MANUAL', 'invalid workspace');
        RAISE EXCEPTION 'cross-workspace attribution was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    INSERT INTO petos.automation_rule
        (workspace_id, name, metric_code, comparator, threshold, pet_id, action_kind, severity)
        VALUES (home_id, 'weight below four', 'weight_kg', 'LT', 4, pet_a_id, 'ALERT', 'WARNING')
        RETURNING id INTO rule_id;
    INSERT INTO petos.automation_execution
        (workspace_id, rule_id, measurement_id, action_kind)
        VALUES (home_id, rule_id, weight_id, 'ALERT') RETURNING id INTO execution_id;
    BEGIN
        INSERT INTO petos.alert_event
            (workspace_id, automation_execution_id, pet_id, severity, title)
            VALUES (home_id, execution_id, pet_b_id, 'WARNING', 'Wrong pet');
        RAISE EXCEPTION 'alert for wrong pet was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    INSERT INTO petos.alert_event
        (workspace_id, automation_execution_id, pet_id, severity, title)
        VALUES (home_id, execution_id, pet_a_id, 'WARNING', 'Low weight');
    UPDATE petos.automation_execution SET status = 'SUCCEEDED', completed_at = now()
        WHERE id = execution_id;
    BEGIN
        UPDATE petos.automation_execution SET status = 'FAILED', completed_at = now()
            WHERE id = execution_id;
        RAISE EXCEPTION 'completed execution was changed';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
    END;
    BEGIN
        INSERT INTO petos.automation_execution
            (workspace_id, rule_id, measurement_id, action_kind)
            VALUES (home_id, rule_id, weight_id, 'ALERT');
        RAISE EXCEPTION 'duplicate automation execution was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    INSERT INTO petos.measurement
        (workspace_id, device_id, source_kind, source_event_id, metric_code, value, measured_at)
        VALUES (home_id, scale_id, 'DEVICE', 'weight-2', 'weight_kg', 3.7000, '2030-01-12')
        RETURNING id INTO second_weight_id;
    INSERT INTO petos.measurement_attribution
        (workspace_id, measurement_id, pet_id, method, reason)
        VALUES (home_id, second_weight_id, pet_a_id, 'BINDING', 'private scale binding');
    INSERT INTO petos.automation_rule
        (workspace_id, name, metric_code, comparator, threshold, pet_id,
         action_kind, severity, cooldown_seconds)
        VALUES (home_id, 'cooldown rule', 'weight_kg', 'LT', 4, pet_a_id,
                'ALERT', 'INFO', 3600)
        RETURNING id INTO cooldown_rule_id;
    INSERT INTO petos.automation_execution
        (workspace_id, rule_id, measurement_id, action_kind)
        VALUES (home_id, cooldown_rule_id, weight_id, 'ALERT');
    BEGIN
        INSERT INTO petos.automation_execution
            (workspace_id, rule_id, measurement_id, action_kind)
            VALUES (home_id, cooldown_rule_id, second_weight_id, 'ALERT');
        RAISE EXCEPTION 'cooldown period was ignored';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    INSERT INTO petos.automation_rule
        (workspace_id, name, metric_code, comparator, threshold, pet_id,
         action_kind, severity)
        VALUES (home_id, 'action required', 'weight_kg', 'LT', 4, pet_a_id,
                'ALERT', 'INFO')
        RETURNING id INTO orphan_rule_id;
    BEGIN
        INSERT INTO petos.automation_execution
            (workspace_id, rule_id, measurement_id, action_kind, status, completed_at)
            VALUES (home_id, orphan_rule_id, second_weight_id, 'ALERT', 'SUCCEEDED', now());
        SET CONSTRAINTS petos.execution_action_at_commit IMMEDIATE;
        RAISE EXCEPTION 'successful execution without an action was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO petos.automation_rule
            (workspace_id, name, metric_code, comparator, threshold, pet_id,
             action_kind, severity)
            VALUES (home_id, 'invalid threshold', 'weight_kg', 'LT', 300, pet_a_id,
                    'ALERT', 'WARNING');
        RAISE EXCEPTION 'out-of-range rule threshold was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM petos.v_pet_latest_weight
        WHERE workspace_id = home_id AND pet_id = pet_a_id AND weight_kg = 3.7000
    ) THEN
        RAISE EXCEPTION 'latest weight view returned wrong result';
    END IF;
    RAISE NOTICE 'PetOS schema tests passed';
END;
$$;

ROLLBACK;
