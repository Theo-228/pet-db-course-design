package com.petos.automation;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.petos.auth.AccessService;
import com.petos.auth.AppPrincipal;
import com.petos.common.ApiException;
import com.petos.device.DeviceMapper;
import com.petos.measurement.MeasurementMapper;
import com.petos.pet.PetMapper;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AutomationService {
    private final AccessService access;
    private final AutomationMapper mapper;
    private final MeasurementMapper metrics;
    private final DeviceMapper devices;
    private final PetMapper pets;
    private final ObjectMapper json;

    public AutomationService(AccessService access, AutomationMapper mapper,
                             MeasurementMapper metrics, DeviceMapper devices,
                             PetMapper pets, ObjectMapper json) {
        this.access = access; this.mapper = mapper; this.metrics = metrics;
        this.devices = devices; this.pets = pets; this.json = json;
    }

    public List<AutomationMapper.Rule> rules(AppPrincipal user, long workspaceId) {
        access.read(user, workspaceId); return mapper.rules(workspaceId);
    }
    public List<AutomationMapper.Execution> executions(AppPrincipal user, long workspaceId) {
        access.read(user, workspaceId); return mapper.executions(workspaceId);
    }
    public List<AutomationMapper.Alert> alerts(AppPrincipal user, long workspaceId) {
        access.read(user, workspaceId); return mapper.alerts(workspaceId);
    }

    @Transactional
    public long create(AppPrincipal user, long workspaceId, AutomationController.RuleInput input) {
        access.write(user, workspaceId);
        if (metrics.metrics().stream().noneMatch(m -> m.code().equals(input.metricCode()))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "未知指标");
        }
        if (input.sourceDeviceId() != null && devices.find(workspaceId, input.sourceDeviceId()) == null
            || input.targetDeviceId() != null && devices.find(workspaceId, input.targetDeviceId()) == null
            || input.petId() != null && pets.find(workspaceId, input.petId()) == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "规则关联的宠物或设备不存在");
        }
        if ("ALERT".equals(input.actionKind()) && input.targetDeviceId() != null
            || "DEVICE_COMMAND".equals(input.actionKind()) && input.targetDeviceId() == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "规则动作目标不匹配");
        }
        Map<String, Object> payload = input.actionPayload();
        if ("DEVICE_COMMAND".equals(input.actionKind())) {
            Object command = payload.get("command_type");
            if (!(command instanceof String s) || !List.of("PING", "DISPENSE", "TARE").contains(s)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "仅支持模拟 PING、DISPENSE、TARE 指令");
            }
            DeviceMapper.Device target = devices.find(workspaceId, input.targetDeviceId());
            if ("RETIRED".equals(target.status())) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "目标设备已停用");
            }
            if ("DISPENSE".equals(command)
                && !("FEEDER".equals(target.kind()) || "WATERER".equals(target.kind()))
                || "TARE".equals(command) && !"SCALE".equals(target.kind())) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "目标设备不支持该指令");
            }
            if ("DISPENSE".equals(command)) {
                Object amount = payload.get("amount");
                if (!(amount instanceof Number number) || number.doubleValue() <= 0
                    || number.doubleValue() > 5000) {
                    throw new ApiException(HttpStatus.BAD_REQUEST, "模拟投放量须在 0 到 5000 之间");
                }
            }
        }
        try {
            return mapper.create(workspaceId, input.name().trim(), input.metricCode(),
                input.comparator(), input.threshold(), input.sourceDeviceId(), input.petId(),
                input.actionKind(), input.targetDeviceId(), json.writeValueAsString(payload),
                input.severity(), input.cooldownSeconds());
        } catch (JsonProcessingException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "动作参数无效");
        }
    }

    @Transactional
    public void enable(AppPrincipal user, long workspaceId, long ruleId, boolean enabled) {
        access.write(user, workspaceId);
        if (mapper.enable(workspaceId, ruleId, enabled) == 0)
            throw new ApiException(HttpStatus.NOT_FOUND, "规则不存在");
    }

    @Transactional
    public void resolve(AppPrincipal user, long workspaceId, long alertId) {
        access.write(user, workspaceId);
        if (mapper.resolve(workspaceId, alertId) == 0)
            throw new ApiException(HttpStatus.NOT_FOUND, "待处理告警不存在");
    }
}
