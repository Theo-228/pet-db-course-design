package com.petos.device;

import com.petos.auth.AppPrincipal;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
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
@RequestMapping("/api/workspaces/{workspaceId}/devices")
public class DeviceController {
    public record DeviceInput(Long spaceId,
                              @NotBlank @Size(max = 120) String serialNumber,
                              @NotBlank @Size(max = 120) String name,
                              @NotNull @Pattern(regexp = "COLLAR|SCALE|FEEDER|WATERER|ENVIRONMENT") String kind,
                              @NotNull @Pattern(regexp = "DEDICATED|SHARED") String sharingPolicy) {}
    public record DeviceUpdate(@NotBlank @Size(max = 120) String name, Long spaceId) {}
    public record StatusInput(@NotNull @Pattern(regexp = "ONLINE|OFFLINE") String status) {}
    public record BindInput(@NotNull Long petId) {}
    public record CommandInput(@NotNull @Pattern(regexp = "PING|DISPENSE|TARE") String commandType,
                               @NotNull Map<String, Object> payload) {}

    private final DeviceService service;

    public DeviceController(DeviceService service) { this.service = service; }

    @GetMapping
    public List<DeviceMapper.Device> list(@AuthenticationPrincipal AppPrincipal user,
                                          @PathVariable long workspaceId) {
        return service.list(user, workspaceId);
    }

    @GetMapping("/{deviceId}")
    public DeviceMapper.Device get(@AuthenticationPrincipal AppPrincipal user,
                                   @PathVariable long workspaceId, @PathVariable long deviceId) {
        return service.get(user, workspaceId, deviceId);
    }

    @PostMapping
    public Map<String, Long> create(@AuthenticationPrincipal AppPrincipal user,
                                    @PathVariable long workspaceId,
                                    @Valid @RequestBody DeviceInput input) {
        return Map.of("id", service.create(user, workspaceId, input));
    }

    @PutMapping("/{deviceId}")
    public void update(@AuthenticationPrincipal AppPrincipal user, @PathVariable long workspaceId,
                       @PathVariable long deviceId, @Valid @RequestBody DeviceUpdate input) {
        service.update(user, workspaceId, deviceId, input);
    }

    @PostMapping("/{deviceId}/status")
    public void status(@AuthenticationPrincipal AppPrincipal user, @PathVariable long workspaceId,
                       @PathVariable long deviceId, @Valid @RequestBody StatusInput input) {
        service.setStatus(user, workspaceId, deviceId, input.status());
    }

    @GetMapping("/{deviceId}/bindings")
    public List<DeviceMapper.Binding> bindings(@AuthenticationPrincipal AppPrincipal user,
                                               @PathVariable long workspaceId,
                                               @PathVariable long deviceId) {
        return service.bindings(user, workspaceId, deviceId);
    }

    @PostMapping("/{deviceId}/bindings")
    public Map<String, Long> bind(@AuthenticationPrincipal AppPrincipal user,
                                  @PathVariable long workspaceId, @PathVariable long deviceId,
                                  @Valid @RequestBody BindInput input) {
        return Map.of("id", service.bind(user, workspaceId, deviceId, input.petId()));
    }

    @PostMapping("/{deviceId}/bindings/{bindingId}/close")
    public void unbind(@AuthenticationPrincipal AppPrincipal user, @PathVariable long workspaceId,
                       @PathVariable long deviceId, @PathVariable long bindingId) {
        service.unbind(user, workspaceId, deviceId, bindingId);
    }

    @PostMapping("/{deviceId}/commands")
    public Map<String, Long> command(@AuthenticationPrincipal AppPrincipal user,
                                     @PathVariable long workspaceId, @PathVariable long deviceId,
                                     @Valid @RequestBody CommandInput input) {
        return Map.of("id", service.simulateCommand(user, workspaceId, deviceId, input));
    }

    @GetMapping("/{deviceId}/commands")
    public List<DeviceMapper.Command> commands(@AuthenticationPrincipal AppPrincipal user,
                                               @PathVariable long workspaceId,
                                               @PathVariable long deviceId) {
        return service.commands(user, workspaceId, deviceId);
    }
}
