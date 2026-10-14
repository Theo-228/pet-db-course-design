package com.petos.pet;

import com.petos.auth.AppPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.time.LocalDate;
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
@RequestMapping("/api/workspaces/{workspaceId}/pets")
public class PetController {
    public record PetInput(@NotBlank @Size(max = 120) String name,
                           @NotBlank @Size(max = 80) String species,
                           String breed,
                           @NotNull @Pattern(regexp = "FEMALE|MALE|UNKNOWN") String sex,
                           LocalDate birthDate,
                           @NotNull @Pattern(regexp = "ACTIVE|OBSERVATION") String status) {}
    public record HealthInput(@NotNull @Pattern(regexp = "OBSERVATION|VACCINATION|TREATMENT|VET_VISIT") String kind,
                              @NotNull Instant occurredAt,
                              @NotBlank @Size(max = 2000) String note) {}

    private final PetService service;

    public PetController(PetService service) {
        this.service = service;
    }

    @GetMapping
    public List<PetMapper.Pet> list(@AuthenticationPrincipal AppPrincipal user,
                                    @PathVariable long workspaceId) {
        return service.list(user, workspaceId);
    }

    @GetMapping("/{petId}")
    public PetMapper.Pet get(@AuthenticationPrincipal AppPrincipal user,
                             @PathVariable long workspaceId, @PathVariable long petId) {
        return service.get(user, workspaceId, petId);
    }

    @PostMapping
    public Map<String, Long> create(@AuthenticationPrincipal AppPrincipal user,
                                    @PathVariable long workspaceId,
                                    @Valid @RequestBody PetInput input) {
        return Map.of("id", service.create(user, workspaceId, input));
    }

    @PutMapping("/{petId}")
    public void update(@AuthenticationPrincipal AppPrincipal user, @PathVariable long workspaceId,
                       @PathVariable long petId, @Valid @RequestBody PetInput input) {
        service.update(user, workspaceId, petId, input);
    }

    @PostMapping("/{petId}/retire")
    public void retire(@AuthenticationPrincipal AppPrincipal user, @PathVariable long workspaceId,
                       @PathVariable long petId) {
        service.retire(user, workspaceId, petId);
    }

    @GetMapping("/{petId}/health-records")
    public List<PetMapper.HealthRecord> healthRecords(@AuthenticationPrincipal AppPrincipal user,
                                                       @PathVariable long workspaceId,
                                                       @PathVariable long petId) {
        return service.healthRecords(user, workspaceId, petId);
    }

    @GetMapping("/{petId}/report")
    public PetService.Report report(@AuthenticationPrincipal AppPrincipal user,
                                     @PathVariable long workspaceId, @PathVariable long petId) {
        return service.report(user, workspaceId, petId);
    }

    @PostMapping("/{petId}/health-records")
    public Map<String, Long> addHealthRecord(@AuthenticationPrincipal AppPrincipal user,
                                             @PathVariable long workspaceId, @PathVariable long petId,
                                             @Valid @RequestBody HealthInput input) {
        return Map.of("id", service.addHealthRecord(user, workspaceId, petId, input));
    }
}
