package com.petos.device;

import java.time.Instant;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

@Mapper
public interface DeviceMapper {
    record Device(long id, long workspaceId, Long spaceId, String serialNumber,
                  String name, String kind, String sharingPolicy, String status,
                  Instant lastSeenAt, Instant createdAt) {}
    record Binding(long id, long deviceId, long petId, String petName,
                   String sharingPolicy, Instant boundAt, Instant unboundAt) {}
    record Command(long id, long deviceId, String commandType, String status,
                   String payload, Instant requestedAt, Instant completedAt) {}

    @Select("""
        SELECT id, workspace_id, space_id, serial_number, name, kind, sharing_policy,
               status, last_seen_at, created_at
        FROM petos.device WHERE workspace_id = #{workspaceId}
        ORDER BY id DESC LIMIT 500
        """)
    List<Device> list(@Param("workspaceId") long workspaceId);

    @Select("""
        SELECT id, workspace_id, space_id, serial_number, name, kind, sharing_policy,
               status, last_seen_at, created_at
        FROM petos.device WHERE workspace_id = #{workspaceId} AND id = #{id}
        """)
    Device find(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("""
        INSERT INTO petos.device
            (workspace_id, space_id, serial_number, name, kind, sharing_policy)
        VALUES (#{workspaceId}, #{spaceId}, #{serialNumber}, #{name}, #{kind}, #{sharingPolicy})
        RETURNING id
        """)
    long create(@Param("workspaceId") long workspaceId, @Param("spaceId") Long spaceId,
                @Param("serialNumber") String serialNumber, @Param("name") String name,
                @Param("kind") String kind, @Param("sharingPolicy") String sharingPolicy);

    @Update("""
        UPDATE petos.device SET name = #{name}, space_id = #{spaceId}
        WHERE workspace_id = #{workspaceId} AND id = #{id} AND status <> 'RETIRED'
        """)
    int update(@Param("workspaceId") long workspaceId, @Param("id") long id,
               @Param("name") String name, @Param("spaceId") Long spaceId);

    @Update("""
        UPDATE petos.device SET status = #{status}, last_seen_at = now()
        WHERE workspace_id = #{workspaceId} AND id = #{id} AND status <> 'RETIRED'
        """)
    int setStatus(@Param("workspaceId") long workspaceId, @Param("id") long id,
                  @Param("status") String status);

    @Select("""
        SELECT b.id, b.device_id, b.pet_id, p.name AS pet_name, b.sharing_policy,
               b.bound_at, b.unbound_at
        FROM petos.device_pet_binding b
        JOIN petos.pet p ON p.workspace_id = b.workspace_id AND p.id = b.pet_id
        WHERE b.workspace_id = #{workspaceId} AND b.device_id = #{deviceId}
        ORDER BY b.bound_at DESC, b.id DESC
        """)
    List<Binding> bindings(@Param("workspaceId") long workspaceId,
                           @Param("deviceId") long deviceId);

    @Select("""
        INSERT INTO petos.device_pet_binding
            (workspace_id, device_id, pet_id, sharing_policy, bound_at)
        VALUES (#{workspaceId}, #{deviceId}, #{petId}, #{sharingPolicy}, now())
        RETURNING id
        """)
    long bind(@Param("workspaceId") long workspaceId, @Param("deviceId") long deviceId,
              @Param("petId") long petId, @Param("sharingPolicy") String sharingPolicy);

    @Update("""
        UPDATE petos.device_pet_binding SET unbound_at = now()
        WHERE workspace_id = #{workspaceId} AND device_id = #{deviceId}
          AND id = #{bindingId} AND unbound_at IS NULL
        """)
    int unbind(@Param("workspaceId") long workspaceId, @Param("deviceId") long deviceId,
               @Param("bindingId") long bindingId);

    @Select("""
        INSERT INTO petos.device_command
            (workspace_id, device_id, command_type, payload, idempotency_key)
        VALUES (#{workspaceId}, #{deviceId}, #{commandType}, CAST(#{payloadJson} AS jsonb), #{key})
        RETURNING id
        """)
    long createCommand(@Param("workspaceId") long workspaceId, @Param("deviceId") long deviceId,
                       @Param("commandType") String commandType,
                       @Param("payloadJson") String payloadJson, @Param("key") String key);

    @Update("""
        UPDATE petos.device_command SET status = 'APPLIED', completed_at = now()
        WHERE workspace_id = #{workspaceId} AND id = #{id} AND status = 'REQUESTED'
        """)
    int applyCommand(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("""
        SELECT id, device_id, command_type, status, payload::text AS payload,
               requested_at, completed_at
        FROM petos.device_command
        WHERE workspace_id = #{workspaceId} AND device_id = #{deviceId}
        ORDER BY requested_at DESC, id DESC LIMIT 100
        """)
    List<Command> commands(@Param("workspaceId") long workspaceId,
                           @Param("deviceId") long deviceId);
}
