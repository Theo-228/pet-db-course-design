-- 当前归属与未知身份的原始记录
SELECT m.id, m.metric_code, m.value, mt.unit, m.measured_at,
       p.name AS pet_name, m.attribution_method
FROM petos.v_measurement_current m
JOIN petos.metric_type mt ON mt.code = m.metric_code
LEFT JOIN petos.pet p ON p.workspace_id = m.workspace_id AND p.id = m.pet_id
ORDER BY m.measured_at DESC;

-- 一宠一档：最新体重、告警数量
SELECT p.workspace_id, p.id, p.name,
       w.weight_kg, w.measured_at AS weight_measured_at,
       count(a.id) FILTER (WHERE a.status = 'OPEN') AS open_alerts
FROM petos.pet p
LEFT JOIN petos.v_pet_latest_weight w
    ON w.workspace_id = p.workspace_id AND w.pet_id = p.id
LEFT JOIN petos.alert_event a
    ON a.workspace_id = p.workspace_id AND a.pet_id = p.id
GROUP BY p.workspace_id, p.id, p.name, w.weight_kg, w.measured_at
ORDER BY p.workspace_id, p.id;

-- 窗口函数：体重相对上一次测量的变化
SELECT pet_id, measured_at, value AS weight_kg,
       value - lag(value) OVER (
           PARTITION BY workspace_id, pet_id ORDER BY measured_at, id
       ) AS change_from_previous_kg
FROM petos.v_measurement_current
WHERE metric_code = 'weight_kg' AND pet_id IS NOT NULL
ORDER BY pet_id, measured_at;

-- 自动化追踪：规则、原始数据、执行及告警
SELECT r.name AS rule_name, m.metric_code, m.value, e.status AS execution_status,
       a.status AS alert_status, a.title
FROM petos.automation_execution e
JOIN petos.automation_rule r ON r.workspace_id = e.workspace_id AND r.id = e.rule_id
JOIN petos.measurement m ON m.workspace_id = e.workspace_id AND m.id = e.measurement_id
LEFT JOIN petos.alert_event a
    ON a.workspace_id = e.workspace_id AND a.automation_execution_id = e.id
ORDER BY e.triggered_at DESC;
