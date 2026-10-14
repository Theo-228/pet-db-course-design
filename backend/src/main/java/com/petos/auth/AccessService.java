package com.petos.auth;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;

@Service
public class AccessService {
    private final AuthMapper mapper;

    public AccessService(AuthMapper mapper) {
        this.mapper = mapper;
    }

    public void read(AppPrincipal user, long workspaceId) {
        if (user == null || mapper.role(workspaceId, user.id()) == null) {
            throw new AccessDeniedException("workspace not accessible");
        }
    }

    public void write(AppPrincipal user, long workspaceId) {
        String role = user == null ? null : mapper.role(workspaceId, user.id());
        if (!"OWNER".equals(role) && !"EDITOR".equals(role)) {
            throw new AccessDeniedException("workspace is read only");
        }
    }
}
