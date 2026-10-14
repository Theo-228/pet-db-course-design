package com.petos.measurement;

import com.petos.auth.AccessService;
import com.petos.auth.AppPrincipal;
import com.petos.common.ApiException;
import com.petos.device.DeviceMapper;
import com.petos.pet.PetMapper;
import java.time.Instant;
import java.util.List;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class MeasurementService {
    public record Recorded(long workspaceId, long measurementId) {}
    private final AccessService access;
    private final MeasurementMapper mapper;
    private final DeviceMapper devices;
    private final PetMapper pets;
    private final ApplicationEventPublisher events;

    public MeasurementService(AccessService access, MeasurementMapper mapper, DeviceMapper devices,
                              PetMapper pets, ApplicationEventPublisher events) {
        this.access = access;
        this.mapper = mapper;
        this.devices = devices;
        this.pets = pets;
        this.events = events;
    }

    public List<MeasurementMapper.Metric> metrics() { return mapper.metrics(); }

    public List<MeasurementMapper.Measurement> list(AppPrincipal user, long workspaceId,
                                                     Long petId, Long deviceId) {
        access.read(user, workspaceId);
        return mapper.list(workspaceId, petId, deviceId);
    }

    @Transactional
    public long record(AppPrincipal user, long workspaceId, MeasurementController.Input input) {
        access.write(user, workspaceId);
        if (input.measuredAt().isAfter(Instant.now().plusSeconds(300))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "测量时间不能位于未来");
        }
        boolean manual = "MANUAL".equals(input.sourceKind());
        if (manual && (input.deviceId() != null || input.sourceEventId() != null
            || input.spaceId() != null || input.petId() == null)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "人工测量须指定宠物且不能关联设备事件");
        }
        if (!manual && (input.deviceId() == null || input.sourceEventId() == null
            || input.sourceEventId().isBlank() || input.petId() != null)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "设备测量须指定设备和事件编号");
        }
        MeasurementMapper.Metric metric = mapper.metrics().stream()
            .filter(m -> m.code().equals(input.metricCode())).findFirst()
            .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "未知指标"));
        if (manual && !"PET".equals(metric.scope())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "该指标不支持人工记录");
        }
        if (manual && pets.find(workspaceId, input.petId()) == null) {
            throw new ApiException(HttpStatus.NOT_FOUND, "宠物不存在");
        }
        DeviceMapper.Device device = null;
        if (!manual) {
            device = devices.find(workspaceId, input.deviceId());
            if (device == null) throw new ApiException(HttpStatus.NOT_FOUND, "设备不存在");
            if ("RETIRED".equals(device.status())) {
                throw new ApiException(HttpStatus.CONFLICT, "已停用设备不能上传测量");
            }
            if ("SPACE".equals(metric.scope()) &&
                (input.spaceId() == null || !input.spaceId().equals(device.spaceId()))) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "环境测量须使用设备所在区域");
            }
        }
        long id = mapper.insert(workspaceId, input.deviceId(), input.spaceId(), input.sourceKind(),
            input.sourceEventId(), input.metricCode(), input.value(), input.periodStartedAt(),
            input.measuredAt());
        if (manual) {
            mapper.attribute(workspaceId, id, input.petId(), "MANUAL", null, "人工记录");
        } else if ("PET".equals(metric.scope())) {
            Long petId = "DEDICATED".equals(device.sharingPolicy())
                ? mapper.dedicatedPet(workspaceId, device.id(), input.measuredAt()) : null;
            mapper.attribute(workspaceId, id, petId, petId == null ? "UNKNOWN" : "BINDING",
                null, petId == null ? "尚未确定宠物身份" : "专属设备有效绑定");
        }
        events.publishEvent(new Recorded(workspaceId, id));
        return id;
    }

    @Transactional
    public long revise(AppPrincipal user, long workspaceId, long measurementId,
                       MeasurementController.AttributionInput input) {
        access.write(user, workspaceId);
        MeasurementMapper.Measurement measurement = mapper.find(workspaceId, measurementId);
        if (measurement == null) throw new ApiException(HttpStatus.NOT_FOUND, "测量不存在");
        if ("MANUAL".equals(measurement.sourceKind())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "人工测量不可重新归属");
        }
        if (mapper.metrics().stream().noneMatch(m -> m.code().equals(measurement.metricCode())
            && "PET".equals(m.scope()))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "该指标不属于宠物，不能修订归属");
        }
        if (input.petId() != null && pets.find(workspaceId, input.petId()) == null) {
            throw new ApiException(HttpStatus.NOT_FOUND, "宠物不存在");
        }
        String method = input.petId() == null ? "UNKNOWN" : "IDENTIFIED";
        return mapper.attribute(workspaceId, measurementId, input.petId(), method, null,
            input.reason().trim());
    }
}
