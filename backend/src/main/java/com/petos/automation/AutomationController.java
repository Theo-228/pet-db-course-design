package com.petos.automation;

import com.petos.auth.AppPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/workspaces/{workspaceId}")
public class AutomationController {
    public record RuleInput(@NotBlank @Size(max = 120) String name,
                            @NotBlank String metricCode,
                            @NotNull @Pattern(regexp = "GT|GTE|LT|LTE") String comparator,
                            @NotNull BigDecimal threshold, Long sourceDeviceId, Long petId,
                            @NotNull @Pattern(regexp = "ALERT|DEVICE_COMMAND") String actionKind,
                            Long targetDeviceId, @NotNull Map<String, Object> actionPayload,
                            @NotNull @Pattern(regexp = "INFO|WARNING|CRITICAL") String severity,
                            @Min(0) @Max(86400) int cooldownSeconds) {}
    public record ToggleInput(boolean enabled) {}
    private final AutomationService service;
    public AutomationController(AutomationService service) { this.service = service; }

    @GetMapping("/rules")
    public List<AutomationMapper.Rule> rules(@AuthenticationPrincipal AppPrincipal user,
                                            @PathVariable long workspaceId) {
        return service.rules(user, workspaceId);
    }
    @PostMapping("/rules")
    public Map<String, Long> create(@AuthenticationPrincipal AppPrincipal user,
                                    @PathVariable long workspaceId,
                                    @Valid @RequestBody RuleInput input) {
        return Map.of("id", service.create(user, workspaceId, input));
    }
    @PostMapping("/rules/{ruleId}/enabled")
    public void enabled(@AuthenticationPrincipal AppPrincipal user,
                        @PathVariable long workspaceId, @PathVariable long ruleId,
                        @RequestBody ToggleInput input) {
        service.enable(user, workspaceId, ruleId, input.enabled());
    }
    @GetMapping("/executions")
    public List<AutomationMapper.Execution> executions(@AuthenticationPrincipal AppPrincipal user,
                                                       @PathVariable long workspaceId) {
        return service.executions(user, workspaceId);
    }
    @GetMapping("/alerts")
    public List<AutomationMapper.Alert> alerts(@AuthenticationPrincipal AppPrincipal user,
                                               @PathVariable long workspaceId) {
        return service.alerts(user, workspaceId);
    }
    @PostMapping("/alerts/{alertId}/resolve")
    public void resolve(@AuthenticationPrincipal AppPrincipal user,
                        @PathVariable long workspaceId, @PathVariable long alertId) {
        service.resolve(user, workspaceId, alertId);
    }
}
