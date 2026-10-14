DO $$
DECLARE
    workspace_id bigint;
    room_id bigint;
    pet_id bigint;
    collar_id bigint;
    scale_id bigint;
    activity_id bigint;
    weight_id bigint;
    rule_id bigint;
    execution_id bigint;
BEGIN
    INSERT INTO petos.workspace (name) VALUES ('演示空间') RETURNING id INTO workspace_id;
    INSERT INTO petos.space (workspace_id, name) VALUES (workspace_id, '活动区') RETURNING id INTO room_id;
    INSERT INTO petos.pet (workspace_id, name, species, breed, sex)
        VALUES (workspace_id, '奶糖', 'cat', '英国短毛猫', 'FEMALE') RETURNING id INTO pet_id;
    INSERT INTO petos.device (workspace_id, space_id, serial_number, name, kind, sharing_policy, status)
        VALUES (workspace_id, room_id, 'DEMO-COLLAR-001', '奶糖项圈', 'COLLAR', 'DEDICATED', 'ONLINE')
        RETURNING id INTO collar_id;
    INSERT INTO petos.device (workspace_id, space_id, serial_number, name, kind, sharing_policy, status)
        VALUES (workspace_id, room_id, 'DEMO-SCALE-001', '共享体重秤', 'SCALE', 'SHARED', 'ONLINE')
        RETURNING id INTO scale_id;
    INSERT INTO petos.device_pet_binding (workspace_id, device_id, pet_id, sharing_policy, bound_at)
        VALUES (workspace_id, collar_id, pet_id, 'DEDICATED', now() - interval '30 days');
    INSERT INTO petos.device_pet_binding (workspace_id, device_id, pet_id, sharing_policy, bound_at)
        VALUES (workspace_id, scale_id, pet_id, 'SHARED', now() - interval '30 days');
    INSERT INTO petos.measurement
        (workspace_id, device_id, space_id, source_kind, source_event_id,
         metric_code, value, period_started_at, measured_at)
        VALUES (workspace_id, collar_id, room_id, 'DEVICE', 'DEMO-ACTIVITY-001',
                'activity_minutes', 85, now() - interval '3 hours', now() - interval '1 hour')
        RETURNING id INTO activity_id;
    INSERT INTO petos.measurement_attribution
        (workspace_id, measurement_id, pet_id, method, confidence, reason)
        VALUES (workspace_id, activity_id, pet_id, 'BINDING', 1, '专属项圈的有效绑定');
    INSERT INTO petos.measurement
        (workspace_id, device_id, space_id, source_kind, source_event_id, metric_code, value, measured_at)
        VALUES (workspace_id, scale_id, room_id, 'DEVICE', 'DEMO-WEIGHT-001', 'weight_kg', 4.3500, now() - interval '30 minutes')
        RETURNING id INTO weight_id;
    INSERT INTO petos.measurement_attribution
        (workspace_id, measurement_id, pet_id, method, confidence, reason)
        VALUES (workspace_id, weight_id, pet_id, 'IDENTIFIED', 0.9900, '演示身份识别结果');
    INSERT INTO petos.health_record (workspace_id, pet_id, kind, occurred_at, note)
        VALUES (workspace_id, pet_id, 'OBSERVATION', now() - interval '1 day', '精神状态正常；这是演示记录。');
    INSERT INTO petos.automation_rule
        (workspace_id, name, metric_code, comparator, threshold, pet_id, action_kind, severity)
        VALUES (workspace_id, '体重低于演示阈值', 'weight_kg', 'LT', 4.5000, pet_id, 'ALERT', 'WARNING')
        RETURNING id INTO rule_id;
    INSERT INTO petos.automation_execution
        (workspace_id, rule_id, measurement_id, action_kind, status, completed_at)
        VALUES (workspace_id, rule_id, weight_id, 'ALERT', 'SUCCEEDED', now())
        RETURNING id INTO execution_id;
    INSERT INTO petos.alert_event
        (workspace_id, automation_execution_id, pet_id, severity, title, details)
        VALUES (workspace_id, execution_id, pet_id, 'WARNING', '演示阈值告警', '仅演示确定性规则，不代表医学判断。');
END;
$$;
