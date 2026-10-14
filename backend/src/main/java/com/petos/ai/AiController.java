package com.petos.ai;

import com.petos.auth.AccessService;
import com.petos.auth.AppPrincipal;
import com.petos.common.ApiException;
import com.petos.pet.PetMapper;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/workspaces/{workspaceId}/ai")
public class AiController {
    public record HealthAnalysisRequest(@Min(1) @Max(365) int lookbackDays) {}
    public record AssistantRequest(@NotBlank @Size(max = 2000) String question,
                                   Long petId) {}
    public record DecisionRequest(@NotNull Long ruleId,
                                  @NotBlank @Size(max = 1000) String context) {}
    private final AccessService access;
    private final PetMapper pets;
    public AiController(AccessService access, PetMapper pets) {
        this.access = access; this.pets = pets;
    }

    @PostMapping("/health-analysis/{petId}")
    public void health(@AuthenticationPrincipal AppPrincipal user,
                       @PathVariable long workspaceId, @PathVariable long petId,
                       @Valid @RequestBody HealthAnalysisRequest request) {
        access.read(user, workspaceId);
        requirePet(workspaceId, petId);
        throw new ApiException(HttpStatus.NOT_IMPLEMENTED,
            "AI 健康分析仅预留接口；当前版本不生成医学建议");
    }

    @PostMapping("/behavior-recognition/{petId}")
    public void behavior(@AuthenticationPrincipal AppPrincipal user,
                         @PathVariable long workspaceId, @PathVariable long petId) {
        access.read(user, workspaceId);
        requirePet(workspaceId, petId);
        throw new ApiException(HttpStatus.NOT_IMPLEMENTED, "AI 行为识别仅预留接口");
    }

    @PostMapping("/assistant")
    public void assistant(@AuthenticationPrincipal AppPrincipal user,
                          @PathVariable long workspaceId,
                          @Valid @RequestBody AssistantRequest request) {
        access.read(user, workspaceId);
        throw new ApiException(HttpStatus.NOT_IMPLEMENTED,
            "全局 AI 助手仅预留接口；当前版本不连接模型或知识库");
    }

    @PostMapping("/database-query")
    public void databaseQuery(@AuthenticationPrincipal AppPrincipal user,
                              @PathVariable long workspaceId,
                              @Valid @RequestBody AssistantRequest request) {
        access.read(user, workspaceId);
        throw new ApiException(HttpStatus.NOT_IMPLEMENTED, "AI 数据库问答仅预留接口");
    }

    @PostMapping("/automation-decision")
    public void decision(@AuthenticationPrincipal AppPrincipal user,
                         @PathVariable long workspaceId,
                         @Valid @RequestBody DecisionRequest request) {
        access.read(user, workspaceId);
        throw new ApiException(HttpStatus.NOT_IMPLEMENTED, "AI 自动化决策仅预留接口");
    }

    private void requirePet(long workspaceId, long petId) {
        if (pets.find(workspaceId, petId) == null) {
            throw new ApiException(HttpStatus.NOT_FOUND, "宠物不存在");
        }
    }
}
