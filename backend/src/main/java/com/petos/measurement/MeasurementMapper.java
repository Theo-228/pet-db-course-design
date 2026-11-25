package com.petos.measurement;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface MeasurementMapper {
    record HistoryDay(String day, String metricCode, long count, BigDecimal average,
                      BigDecimal minimum, BigDecimal maximum, BigDecimal total,
                      long manualCount, long deviceCount) {}

    @Select("""
        SELECT (v.measured_at AT TIME ZONE 'Asia/Shanghai')::date::text AS day,
               v.metric_code, count(*) AS count, avg(v.value) AS average,
               min(v.value) AS minimum, max(v.value) AS maximum, sum(v.value) AS total,
               count(*) FILTER (WHERE v.source_kind = 'MANUAL') AS manual_count,
               count(*) FILTER (WHERE v.source_kind = 'DEVICE') AS device_count
        FROM petos.v_measurement_current v
        WHERE v.workspace_id = #{workspaceId}
          AND (#{petId}::bigint IS NULL OR v.pet_id = #{petId})
          AND (#{deviceId}::bigint IS NULL OR v.device_id = #{deviceId})
          AND v.measured_at >= (CAST(#{start} AS date)::timestamp AT TIME ZONE 'Asia/Shanghai')
          AND v.measured_at < ((CAST(#{end} AS date) + 1)::timestamp AT TIME ZONE 'Asia/Shanghai')
        GROUP BY 1, 2 ORDER BY 1, 2
        """)
    List<HistoryDay> history(@Param("workspaceId") long workspaceId,
        @Param("petId") Long petId, @Param("deviceId") Long deviceId,
        @Param("start") String start, @Param("end") String end);

    record Metric(String code, String label, String unit, String scope, boolean requiresPeriod) {}
    record Measurement(long id, Long deviceId, Long spaceId, String sourceKind,
                       String metricCode, BigDecimal value, Instant periodStartedAt,
                       Instant measuredAt, Long petId, String attributionMethod,
                       BigDecimal attributionConfidence) {}

    @Select("SELECT code, label, unit, scope, requires_period FROM petos.metric_type ORDER BY code")
    List<Metric> metrics();

    @Select("""
        SELECT v.id, v.device_id, v.space_id, v.source_kind, v.metric_code, v.value,
               m.period_started_at, v.measured_at, v.pet_id, v.attribution_method,
               v.attribution_confidence
        FROM petos.v_measurement_current v JOIN petos.measurement m ON m.id = v.id
        WHERE v.workspace_id = #{workspaceId}
          AND (#{petId}::bigint IS NULL OR v.pet_id = #{petId})
          AND (#{deviceId}::bigint IS NULL OR v.device_id = #{deviceId})
        ORDER BY v.measured_at DESC, v.id DESC LIMIT 200
        """)
    List<Measurement> list(@Param("workspaceId") long workspaceId,
                           @Param("petId") Long petId, @Param("deviceId") Long deviceId);

    @Select("""
        SELECT v.id, v.device_id, v.space_id, v.source_kind, v.metric_code, v.value,
               m.period_started_at, v.measured_at, v.pet_id, v.attribution_method,
               v.attribution_confidence
        FROM petos.v_measurement_current v JOIN petos.measurement m ON m.id = v.id
        WHERE v.workspace_id = #{workspaceId} AND v.id = #{id}
        """)
    Measurement find(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("""
        INSERT INTO petos.measurement (workspace_id, device_id, space_id, source_kind,
              source_event_id, metric_code, value, period_started_at, measured_at)
        VALUES (#{workspaceId}, #{deviceId}, #{spaceId}, #{sourceKind}, #{eventId},
              #{metricCode}, #{value}, #{periodStartedAt}, #{measuredAt}) RETURNING id
        """)
    long insert(@Param("workspaceId") long workspaceId, @Param("deviceId") Long deviceId,
                @Param("spaceId") Long spaceId, @Param("sourceKind") String sourceKind,
                @Param("eventId") String eventId, @Param("metricCode") String metricCode,
                @Param("value") BigDecimal value,
                @Param("periodStartedAt") Instant periodStartedAt,
                @Param("measuredAt") Instant measuredAt);

    @Select("""
        SELECT p.id FROM petos.device_pet_binding b
        JOIN petos.pet p ON p.workspace_id = b.workspace_id AND p.id = b.pet_id
        WHERE b.workspace_id = #{workspaceId} AND b.device_id = #{deviceId}
          AND b.sharing_policy = 'DEDICATED' AND p.status <> 'RETIRED'
          AND b.bound_at <= #{measuredAt}
          AND (b.unbound_at IS NULL OR #{measuredAt} < b.unbound_at)
        LIMIT 1
        """)
    Long dedicatedPet(@Param("workspaceId") long workspaceId,
                      @Param("deviceId") long deviceId,
                      @Param("measuredAt") Instant measuredAt);

    @Select("""
        INSERT INTO petos.measurement_attribution
          (workspace_id, measurement_id, pet_id, method, confidence, reason)
        VALUES (#{workspaceId}, #{measurementId}, #{petId}, #{method},
                #{confidence}, #{reason}) RETURNING id
        """)
    long attribute(@Param("workspaceId") long workspaceId,
                   @Param("measurementId") long measurementId, @Param("petId") Long petId,
                   @Param("method") String method, @Param("confidence") BigDecimal confidence,
                   @Param("reason") String reason);
}
