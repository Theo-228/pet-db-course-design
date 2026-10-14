package com.petos.auth;

import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface AuthMapper {
    record Account(long id, String loginName, String passwordHash, String status) {}
    record Membership(long workspaceId, String workspaceName, String role) {}

    @Select("""
        SELECT id, login_name, password_hash, status
        FROM petos.user_account WHERE lower(login_name) = lower(#{loginName})
        """)
    Account findByLogin(@Param("loginName") String loginName);

    @Select("""
        INSERT INTO petos.user_account (login_name, password_hash)
        VALUES (#{loginName}, #{passwordHash}) RETURNING id
        """)
    long createAccount(@Param("loginName") String loginName, @Param("passwordHash") String passwordHash);

    @Select("""
        INSERT INTO petos.workspace (name) VALUES (#{name}) RETURNING id
        """)
    long createWorkspace(@Param("name") String name);

    @Select("""
        INSERT INTO petos.workspace_membership (workspace_id, user_id, role)
        VALUES (#{workspaceId}, #{userId}, 'OWNER') RETURNING workspace_id
        """)
    long addOwner(@Param("workspaceId") long workspaceId, @Param("userId") long userId);

    @Select("""
        SELECT m.workspace_id, w.name AS workspace_name, m.role
        FROM petos.workspace_membership m
        JOIN petos.workspace w ON w.id = m.workspace_id
        WHERE m.user_id = #{userId} AND m.revoked_at IS NULL AND w.archived_at IS NULL
        ORDER BY m.workspace_id
        """)
    List<Membership> memberships(@Param("userId") long userId);

    @Select("""
        SELECT role FROM petos.workspace_membership
        WHERE workspace_id = #{workspaceId} AND user_id = #{userId} AND revoked_at IS NULL
        """)
    String role(@Param("workspaceId") long workspaceId, @Param("userId") long userId);
}
