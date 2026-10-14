package com.petos.workspace;

import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

@Mapper
public interface WorkspaceMapper {
    record Space(long id, long workspaceId, String name) {}

    @Select("""
        SELECT id, workspace_id, name FROM petos.space
        WHERE workspace_id = #{workspaceId} ORDER BY id
        """)
    List<Space> spaces(@Param("workspaceId") long workspaceId);

    @Select("""
        INSERT INTO petos.space (workspace_id, name)
        VALUES (#{workspaceId}, #{name}) RETURNING id
        """)
    long createSpace(@Param("workspaceId") long workspaceId, @Param("name") String name);

    @Update("""
        UPDATE petos.space SET name = #{name}
        WHERE workspace_id = #{workspaceId} AND id = #{id}
        """)
    int renameSpace(@Param("workspaceId") long workspaceId, @Param("id") long id,
                    @Param("name") String name);
}
