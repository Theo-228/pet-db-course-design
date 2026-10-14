package com.petos.pet;

import java.time.Instant;
import java.time.LocalDate;
import java.math.BigDecimal;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

@Mapper
public interface PetMapper {
    record Pet(long id, long workspaceId, String name, String species, String breed,
               String sex, LocalDate birthDate, String status, Instant createdAt, Instant retiredAt) {}
    record HealthRecord(long id, long workspaceId, long petId, String kind,
                        Instant occurredAt, String note, Instant createdAt) {}
    record LatestWeight(BigDecimal weightKg, Instant measuredAt) {}
    record DailyTotal(LocalDate localDay, BigDecimal activityMinutes,
                      BigDecimal foodIntakeG, BigDecimal waterIntakeMl) {}

    @Select("""
        SELECT id, workspace_id, name, species, breed, sex, birth_date, status, created_at, retired_at
        FROM petos.pet WHERE workspace_id = #{workspaceId}
        ORDER BY CASE WHEN status = 'RETIRED' THEN 1 ELSE 0 END, id DESC LIMIT 500
        """)
    List<Pet> list(@Param("workspaceId") long workspaceId);

    @Select("""
        SELECT id, workspace_id, name, species, breed, sex, birth_date, status, created_at, retired_at
        FROM petos.pet WHERE workspace_id = #{workspaceId} AND id = #{id}
        """)
    Pet find(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("""
        INSERT INTO petos.pet (workspace_id, name, species, breed, sex, birth_date)
        VALUES (#{workspaceId}, #{name}, #{species}, #{breed}, #{sex}, #{birthDate})
        RETURNING id
        """)
    long create(@Param("workspaceId") long workspaceId, @Param("name") String name,
                @Param("species") String species, @Param("breed") String breed,
                @Param("sex") String sex, @Param("birthDate") LocalDate birthDate);

    @Update("""
        UPDATE petos.pet SET name = #{name}, species = #{species}, breed = #{breed},
            sex = #{sex}, birth_date = #{birthDate}, status = #{status}
        WHERE workspace_id = #{workspaceId} AND id = #{id} AND status <> 'RETIRED'
        """)
    int update(@Param("workspaceId") long workspaceId, @Param("id") long id,
               @Param("name") String name, @Param("species") String species,
               @Param("breed") String breed, @Param("sex") String sex,
               @Param("birthDate") LocalDate birthDate, @Param("status") String status);

    @Update("""
        UPDATE petos.pet SET status = 'RETIRED', retired_at = now()
        WHERE workspace_id = #{workspaceId} AND id = #{id} AND status <> 'RETIRED'
        """)
    int retire(@Param("workspaceId") long workspaceId, @Param("id") long id);

    @Select("""
        SELECT id, workspace_id, pet_id, kind, occurred_at, note, created_at
        FROM petos.health_record
        WHERE workspace_id = #{workspaceId} AND pet_id = #{petId}
        ORDER BY occurred_at DESC, id DESC LIMIT 200
        """)
    List<HealthRecord> healthRecords(@Param("workspaceId") long workspaceId,
                                     @Param("petId") long petId);

    @Select("""
        INSERT INTO petos.health_record (workspace_id, pet_id, kind, occurred_at, note)
        VALUES (#{workspaceId}, #{petId}, #{kind}, #{occurredAt}, #{note}) RETURNING id
        """)
    long addHealthRecord(@Param("workspaceId") long workspaceId, @Param("petId") long petId,
                         @Param("kind") String kind, @Param("occurredAt") Instant occurredAt,
                         @Param("note") String note);

    @Select("""
        SELECT weight_kg, measured_at FROM petos.v_pet_latest_weight
        WHERE workspace_id = #{workspaceId} AND pet_id = #{petId}
        """)
    LatestWeight latestWeight(@Param("workspaceId") long workspaceId,
                              @Param("petId") long petId);

    @Select("""
        SELECT local_day, activity_minutes, food_intake_g, water_intake_ml
        FROM petos.v_pet_daily_totals
        WHERE workspace_id = #{workspaceId} AND pet_id = #{petId}
          AND local_day >= (now() AT TIME ZONE 'Asia/Shanghai')::date - 29
        ORDER BY local_day DESC LIMIT 30
        """)
    List<DailyTotal> dailyTotals(@Param("workspaceId") long workspaceId,
                                  @Param("petId") long petId);
}
