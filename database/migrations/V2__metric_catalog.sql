INSERT INTO petos.metric_type (code, label, unit, scope, minimum, maximum) VALUES
    ('weight_kg', '体重', 'kg', 'PET', 0.0100, 200.0000),
    ('activity_minutes', '活动时长', 'min', 'PET', 0.0000, 1440.0000),
    ('food_intake_g', '进食量', 'g', 'PET', 0.0000, 5000.0000),
    ('water_intake_ml', '饮水量', 'ml', 'PET', 0.0000, 5000.0000),
    ('food_dispensed_g', '设备出粮量', 'g', 'DEVICE', 0.0000, 5000.0000),
    ('water_dispensed_ml', '设备出水量', 'ml', 'DEVICE', 0.0000, 5000.0000),
    ('battery_pct', '电量', '%', 'DEVICE', 0.0000, 100.0000),
    ('ambient_temp_c', '环境温度', '°C', 'SPACE', -40.0000, 85.0000),
    ('humidity_pct', '环境湿度', '%', 'SPACE', 0.0000, 100.0000);

INSERT INTO petos.device_metric_capability (device_kind, metric_code) VALUES
    ('COLLAR', 'activity_minutes'),
    ('COLLAR', 'battery_pct'),
    ('SCALE', 'weight_kg'),
    ('SCALE', 'battery_pct'),
    ('FEEDER', 'food_intake_g'),
    ('FEEDER', 'food_dispensed_g'),
    ('FEEDER', 'battery_pct'),
    ('WATERER', 'water_intake_ml'),
    ('WATERER', 'water_dispensed_ml'),
    ('WATERER', 'battery_pct'),
    ('ENVIRONMENT', 'ambient_temp_c'),
    ('ENVIRONMENT', 'humidity_pct'),
    ('ENVIRONMENT', 'battery_pct');
