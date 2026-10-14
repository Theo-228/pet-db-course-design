CREATE VIEW petos.v_measurement_current AS
SELECT m.id,
       m.workspace_id,
       m.device_id,
       m.space_id,
       m.source_kind,
       m.source_event_id,
       m.metric_code,
       m.value,
       m.measured_at,
       m.recorded_at,
       a.pet_id,
       COALESCE(a.method, 'UNKNOWN') AS attribution_method,
       a.confidence AS attribution_confidence,
       a.id AS attribution_revision_id
FROM petos.measurement m
LEFT JOIN LATERAL (
    SELECT x.id, x.pet_id, x.method, x.confidence
    FROM petos.measurement_attribution x
    WHERE x.workspace_id = m.workspace_id AND x.measurement_id = m.id
    ORDER BY x.id DESC
    LIMIT 1
) a ON true;

CREATE VIEW petos.v_pet_latest_weight AS
SELECT DISTINCT ON (workspace_id, pet_id)
       workspace_id, pet_id, value AS weight_kg, measured_at, id AS measurement_id
FROM petos.v_measurement_current
WHERE metric_code = 'weight_kg' AND pet_id IS NOT NULL
ORDER BY workspace_id, pet_id, measured_at DESC, id DESC;

CREATE VIEW petos.v_pet_daily_totals AS
SELECT workspace_id,
       pet_id,
       (measured_at AT TIME ZONE 'Asia/Shanghai')::date AS local_day,
       sum(value) FILTER (WHERE metric_code = 'activity_minutes') AS activity_minutes,
       sum(value) FILTER (WHERE metric_code = 'food_intake_g') AS food_intake_g,
       sum(value) FILTER (WHERE metric_code = 'water_intake_ml') AS water_intake_ml
FROM petos.v_measurement_current
WHERE pet_id IS NOT NULL
  AND metric_code IN ('activity_minutes', 'food_intake_g', 'water_intake_ml')
GROUP BY workspace_id, pet_id, (measured_at AT TIME ZONE 'Asia/Shanghai')::date;

CREATE VIEW petos.v_device_last_measurement AS
SELECT DISTINCT ON (workspace_id, device_id)
       workspace_id, device_id, metric_code, value, measured_at
FROM petos.measurement
WHERE device_id IS NOT NULL
ORDER BY workspace_id, device_id, measured_at DESC, id DESC;

COMMENT ON VIEW petos.v_measurement_current IS 'Raw measurement plus latest attribution revision; unknown identity remains NULL';
COMMENT ON VIEW petos.v_pet_daily_totals IS 'Daily totals use Asia/Shanghai calendar days for the current course deployment';
