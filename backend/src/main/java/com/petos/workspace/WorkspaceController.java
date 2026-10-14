package com.petos.workspace;

import com.petos.auth.AppPrincipal;
import com.petos.auth.AuthMapper;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.Map;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/workspaces")
public class WorkspaceController {
    public record NameInput(@NotBlank @Size(max = 120) String name) {}

    private final AuthMapper auth;
    private final WorkspaceService service;

    public WorkspaceController(AuthMapper auth, WorkspaceService service) {
        this.auth = auth;
        this.service = service;
    }

    @GetMapping
    public List<AuthMapper.Membership> list(@AuthenticationPrincipal AppPrincipal user) {
        return auth.memberships(user.id());
    }

    @PostMapping
    public Map<String, Long> create(@AuthenticationPrincipal AppPrincipal user,
                                    @Valid @RequestBody NameInput input) {
        return Map.of("id", service.create(user, input.name()));
    }

    @GetMapping("/{workspaceId}/spaces")
    public List<WorkspaceMapper.Space> spaces(@AuthenticationPrincipal AppPrincipal user,
                                              @PathVariable long workspaceId) {
        return service.spaces(user, workspaceId);
    }

    @PostMapping("/{workspaceId}/spaces")
    public Map<String, Long> addSpace(@AuthenticationPrincipal AppPrincipal user,
                                      @PathVariable long workspaceId,
                                      @Valid @RequestBody NameInput input) {
        return Map.of("id", service.addSpace(user, workspaceId, input.name()));
    }

    @PutMapping("/{workspaceId}/spaces/{spaceId}")
    public void renameSpace(@AuthenticationPrincipal AppPrincipal user,
                            @PathVariable long workspaceId, @PathVariable long spaceId,
                            @Valid @RequestBody NameInput input) {
        service.renameSpace(user, workspaceId, spaceId, input.name());
    }
}
