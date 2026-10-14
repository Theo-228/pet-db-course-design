package com.petos.workspace;

import com.petos.auth.AccessService;
import com.petos.auth.AppPrincipal;
import com.petos.auth.AuthMapper;
import com.petos.common.ApiException;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class WorkspaceService {
    private final AuthMapper auth;
    private final WorkspaceMapper spaces;
    private final AccessService access;

    public WorkspaceService(AuthMapper auth, WorkspaceMapper spaces, AccessService access) {
        this.auth = auth;
        this.spaces = spaces;
        this.access = access;
    }

    @Transactional
    public long create(AppPrincipal user, String name) {
        long id = auth.createWorkspace(name.trim());
        auth.addOwner(id, user.id());
        return id;
    }

    public List<WorkspaceMapper.Space> spaces(AppPrincipal user, long workspaceId) {
        access.read(user, workspaceId);
        return spaces.spaces(workspaceId);
    }

    @Transactional
    public long addSpace(AppPrincipal user, long workspaceId, String name) {
        access.write(user, workspaceId);
        return spaces.createSpace(workspaceId, name.trim());
    }

    @Transactional
    public void renameSpace(AppPrincipal user, long workspaceId, long spaceId, String name) {
        access.write(user, workspaceId);
        if (spaces.renameSpace(workspaceId, spaceId, name.trim()) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "空间不存在");
        }
    }
}
