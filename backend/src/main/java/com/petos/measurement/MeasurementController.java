package com.petos.measurement;

import com.petos.auth.AppPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class MeasurementController {
    public record Input(@NotNull @Pattern(regexp = "DEVICE|MANUAL") String sourceKind,
                        Long deviceId, Long spaceId, Long petId,
                        @Size(max = 120) String sourceEventId,
                        @NotBlank String metricCode, @NotNull BigDecimal value,
                        Instant periodStartedAt, @NotNull Instant measuredAt) {}
    public record AttributionInput(Long petId, @NotBlank @Size(max = 500) String reason) {}
    private final MeasurementService service;

    public MeasurementController(MeasurementService service) { this.service = service; }

    @GetMapping("/metrics")
    public List<MeasurementMapper.Metric> metrics() { return service.metrics(); }

    @GetMapping("/workspaces/{workspaceId}/measurements")
    public List<MeasurementMapper.Measurement> list(@AuthenticationPrincipal AppPrincipal user,
        @PathVariable long workspaceId, @RequestParam(required = false) Long petId,
        @RequestParam(required = false) Long deviceId) {
        return service.list(user, workspaceId, petId, deviceId);
    }

    @PostMapping("/workspaces/{workspaceId}/measurements")
    public Map<String, Long> record(@AuthenticationPrincipal AppPrincipal user,
        @PathVariable long workspaceId, @Valid @RequestBody Input input) {
        return Map.of("id", service.record(user, workspaceId, input));
    }

    @PostMapping("/workspaces/{workspaceId}/measurements/{measurementId}/attributions")
    public Map<String, Long> revise(@AuthenticationPrincipal AppPrincipal user,
        @PathVariable long workspaceId, @PathVariable long measurementId,
        @Valid @RequestBody AttributionInput input) {
        return Map.of("id", service.revise(user, workspaceId, measurementId, input));
    }
}
