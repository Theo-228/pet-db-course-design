package com.petos.automation;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

@Mapper
public interface AutomationMapper {
    record Rule(long id, String name, boolean enabled, String metricCode, String comparator,
                BigDecimal threshold, Long sourceDeviceId, Long petId, String actionKind,
                Long targetDeviceId, String actionPayload, String severity, int cooldownSeconds) {}
    record Execution(long id, long ruleId, long measurementId, String actionKind,
                     String status, Instant triggeredAt, Instant completedAt, String errorMessage) {}
    record Alert(long id, Long automationExecutionId, Long petId, Long deviceId,
                 String severity, String title, String details, String status,
                 Instant createdAt, Instant resolvedAt) {}

    @Select("""
        SELECT id, name, enabled, metric_code, comparator, threshold, source_device_id,
               pet_id, action_kind, target_device_id, action_payload::text AS action_payload,
               severity, cooldown_seconds
        FROM petos.automation_rule WHERE workspace_id = #{workspaceId} ORDER BY id DESC LIMIT 200
        """)
    List<Rule> rules(@Param("workspaceId") long workspaceId);

    @Select("""
        SELECT id, name, enabled, metric_code, comparator, threshold, source_device_id,
               pet_id, action_kind, target_device_id, action_payload::text AS action_payload,
               severity, cooldown_seconds
        FROM petos.automation_rule WHERE workspace_id = #{workspaceId} AND id = #{id}
        """)
    Rule rule(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("""
        INSERT INTO petos.automation_rule (workspace_id, name, metric_code, comparator,
            threshold, source_device_id, pet_id, action_kind, target_device_id,
            action_payload, severity, cooldown_seconds)
        VALUES (#{workspaceId}, #{name}, #{metricCode}, #{comparator}, #{threshold},
            #{sourceDeviceId}, #{petId}, #{actionKind}, #{targetDeviceId},
            CAST(#{payload} AS jsonb), #{severity}, #{cooldownSeconds}) RETURNING id
        """)
    long create(@Param("workspaceId") long workspaceId, @Param("name") String name,
                @Param("metricCode") String metricCode, @Param("comparator") String comparator,
                @Param("threshold") BigDecimal threshold,
                @Param("sourceDeviceId") Long sourceDeviceId, @Param("petId") Long petId,
                @Param("actionKind") String actionKind, @Param("targetDeviceId") Long targetDeviceId,
                @Param("payload") String payload, @Param("severity") String severity,
                @Param("cooldownSeconds") int cooldownSeconds);

    @Update("""
        UPDATE petos.automation_rule SET enabled = #{enabled}, updated_at = now()
        WHERE workspace_id = #{workspaceId} AND id = #{id}
        """)
    int enable(@Param("workspaceId") long workspaceId, @Param("id") long id,
               @Param("enabled") boolean enabled);

    @Select("""
        SELECT r.id, r.name, r.enabled, r.metric_code, r.comparator, r.threshold,
               r.source_device_id, r.pet_id, r.action_kind, r.target_device_id,
               r.action_payload::text AS action_payload, r.severity, r.cooldown_seconds
        FROM petos.automation_rule r
        JOIN petos.v_measurement_current m ON m.workspace_id = r.workspace_id
          AND m.id = #{measurementId} AND m.metric_code = r.metric_code
        WHERE r.workspace_id = #{workspaceId} AND r.enabled
          AND r.created_at <= m.recorded_at
          AND NOT EXISTS (
              SELECT 1 FROM petos.automation_execution existing
              WHERE existing.rule_id = r.id AND existing.measurement_id = m.id
          )
          AND NOT EXISTS (
              SELECT 1 FROM petos.automation_execution previous
              WHERE previous.rule_id = r.id AND previous.status <> 'SKIPPED'
                AND previous.triggered_at > m.recorded_at
                    - make_interval(secs => r.cooldown_seconds)
                AND previous.triggered_at <= m.recorded_at
          )
          AND (r.source_device_id IS NULL OR r.source_device_id = m.device_id)
          AND (r.pet_id IS NULL OR r.pet_id = m.pet_id)
          AND CASE r.comparator WHEN 'GT' THEN m.value > r.threshold
              WHEN 'GTE' THEN m.value >= r.threshold WHEN 'LT' THEN m.value < r.threshold
              WHEN 'LTE' THEN m.value <= r.threshold ELSE false END
        ORDER BY r.id
        """)
    List<Rule> matches(@Param("workspaceId") long workspaceId,
                       @Param("measurementId") long measurementId);

    record Dispatch(long workspaceId, long measurementId) {}

    @Select("""
        SELECT measurement_id FROM petos.automation_dispatch
        WHERE workspace_id = #{workspaceId} AND measurement_id = #{measurementId}
          AND status = 'PENDING'
        """)
    Long pending(@Param("workspaceId") long workspaceId,
                 @Param("measurementId") long measurementId);

    @Select("""
        SELECT workspace_id, measurement_id FROM petos.automation_dispatch
        WHERE status = 'PENDING' ORDER BY created_at, measurement_id LIMIT 100
        """)
    List<Dispatch> pendingBatch();

    @Update("""
        UPDATE petos.automation_dispatch
        SET status = 'COMPLETED', processed_at = now(), attempts = attempts + 1,
            last_error = NULL
        WHERE workspace_id = #{workspaceId} AND measurement_id = #{measurementId}
          AND status = 'PENDING'
        """)
    int completeDispatch(@Param("workspaceId") long workspaceId,
                         @Param("measurementId") long measurementId);

    @Update("""
        UPDATE petos.automation_dispatch
        SET attempts = attempts + 1, last_error = #{error}
        WHERE workspace_id = #{workspaceId} AND measurement_id = #{measurementId}
          AND status = 'PENDING'
        """)
    int failDispatch(@Param("workspaceId") long workspaceId,
                     @Param("measurementId") long measurementId,
                     @Param("error") String error);

    @Select("""
        INSERT INTO petos.automation_execution
          (workspace_id, rule_id, measurement_id, action_kind, triggered_at)
        SELECT #{workspaceId}, #{ruleId}, m.id, #{actionKind}, m.recorded_at
        FROM petos.measurement m
        WHERE m.workspace_id = #{workspaceId} AND m.id = #{measurementId}
        ON CONFLICT (rule_id, measurement_id) DO NOTHING RETURNING id
        """)
    Long begin(@Param("workspaceId") long workspaceId, @Param("ruleId") long ruleId,
               @Param("measurementId") long measurementId,
               @Param("actionKind") String actionKind);

    @Update("""
        UPDATE petos.automation_execution SET status = #{status}, completed_at = now(),
          error_message = #{errorMessage}
        WHERE workspace_id = #{workspaceId} AND id = #{id} AND status = 'PENDING'
        """)
    int finish(@Param("workspaceId") long workspaceId, @Param("id") long id,
               @Param("status") String status, @Param("errorMessage") String errorMessage);

    @Select("""
        INSERT INTO petos.alert_event (workspace_id, automation_execution_id,
          pet_id, device_id, severity, title, details)
        SELECT #{workspaceId}, #{executionId}, v.pet_id, v.device_id,
          #{severity}, #{title}, #{details}
        FROM petos.v_measurement_current v
        WHERE v.workspace_id = #{workspaceId} AND v.id = #{measurementId}
        RETURNING id
        """)
    long alert(@Param("workspaceId") long workspaceId, @Param("executionId") long executionId,
               @Param("measurementId") long measurementId, @Param("severity") String severity,
               @Param("title") String title, @Param("details") String details);

    @Select("""
        SELECT id, rule_id, measurement_id, action_kind, status, triggered_at,
               completed_at, error_message FROM petos.automation_execution
        WHERE workspace_id = #{workspaceId} ORDER BY id DESC LIMIT 200
        """)
    List<Execution> executions(@Param("workspaceId") long workspaceId);

    @Select("""
        SELECT id, automation_execution_id, pet_id, device_id, severity, title,
               details, status, created_at, resolved_at FROM petos.alert_event
        WHERE workspace_id = #{workspaceId} ORDER BY created_at DESC, id DESC LIMIT 200
        """)
    List<Alert> alerts(@Param("workspaceId") long workspaceId);

    @Update("""
        UPDATE petos.alert_event SET status = 'RESOLVED', resolved_at = now()
        WHERE workspace_id = #{workspaceId} AND id = #{id} AND status = 'OPEN'
        """)
    int resolve(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("SELECT status FROM petos.device WHERE workspace_id = #{workspaceId} AND id = #{id}")
    String deviceStatus(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("""
        INSERT INTO petos.device_command
          (workspace_id, device_id, automation_execution_id, command_type, payload, idempotency_key)
        VALUES (#{workspaceId}, #{deviceId}, #{executionId}, #{commandType},
                CAST(#{payload} AS jsonb), #{key}) RETURNING id
        """)
    long command(@Param("workspaceId") long workspaceId, @Param("deviceId") long deviceId,
                 @Param("executionId") long executionId,
                 @Param("commandType") String commandType, @Param("payload") String payload,
                 @Param("key") String key);
}
