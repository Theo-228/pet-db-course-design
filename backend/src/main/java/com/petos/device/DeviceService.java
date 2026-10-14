package com.petos.device;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.petos.auth.AccessService;
import com.petos.auth.AppPrincipal;
import com.petos.common.ApiException;
import com.petos.pet.PetMapper;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeviceService {
    private final AccessService access;
    private final DeviceMapper mapper;
    private final PetMapper pets;
    private final ObjectMapper json;

    public DeviceService(AccessService access, DeviceMapper mapper, PetMapper pets,
                         ObjectMapper json) {
        this.access = access;
        this.mapper = mapper;
        this.pets = pets;
        this.json = json;
    }

    public List<DeviceMapper.Device> list(AppPrincipal user, long workspaceId) {
        access.read(user, workspaceId);
        return mapper.list(workspaceId);
    }

    public DeviceMapper.Device get(AppPrincipal user, long workspaceId, long deviceId) {
        access.read(user, workspaceId);
        DeviceMapper.Device device = mapper.find(workspaceId, deviceId);
        if (device == null) throw new ApiException(HttpStatus.NOT_FOUND, "设备不存在");
        return device;
    }

    @Transactional
    public long create(AppPrincipal user, long workspaceId, DeviceController.DeviceInput input) {
        access.write(user, workspaceId);
        return mapper.create(workspaceId, input.spaceId(), input.serialNumber().trim(),
            input.name().trim(), input.kind(), input.sharingPolicy());
    }

    @Transactional
    public void update(AppPrincipal user, long workspaceId, long deviceId,
                       DeviceController.DeviceUpdate input) {
        access.write(user, workspaceId);
        if (mapper.update(workspaceId, deviceId, input.name().trim(), input.spaceId()) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "设备不存在或已停用");
        }
    }

    @Transactional
    public void setStatus(AppPrincipal user, long workspaceId, long deviceId, String status) {
        access.write(user, workspaceId);
        if (mapper.setStatus(workspaceId, deviceId, status) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "设备不存在或已停用");
        }
    }

    public List<DeviceMapper.Binding> bindings(AppPrincipal user, long workspaceId, long deviceId) {
        get(user, workspaceId, deviceId);
        return mapper.bindings(workspaceId, deviceId);
    }

    @Transactional
    public long bind(AppPrincipal user, long workspaceId, long deviceId, long petId) {
        access.write(user, workspaceId);
        DeviceMapper.Device device = get(user, workspaceId, deviceId);
        if ("RETIRED".equals(device.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "已停用设备不能建立新绑定");
        }
        var pet = pets.find(workspaceId, petId);
        if (pet == null) {
            throw new ApiException(HttpStatus.NOT_FOUND, "宠物不存在");
        }
        if ("RETIRED".equals(pet.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "已归档宠物不能建立新绑定");
        }
        return mapper.bind(workspaceId, deviceId, petId, device.sharingPolicy());
    }

    @Transactional
    public void unbind(AppPrincipal user, long workspaceId, long deviceId, long bindingId) {
        access.write(user, workspaceId);
        if (mapper.unbind(workspaceId, deviceId, bindingId) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "有效绑定不存在");
        }
    }

    @Transactional
    public long simulateCommand(AppPrincipal user, long workspaceId, long deviceId,
                                DeviceController.CommandInput input) {
        access.write(user, workspaceId);
        DeviceMapper.Device device = get(user, workspaceId, deviceId);
        if (!"ONLINE".equals(device.status())) {
            throw new ApiException(HttpStatus.CONFLICT, "设备离线，不能执行模拟指令");
        }
        boolean supported = switch (input.commandType()) {
            case "PING" -> true;
            case "DISPENSE" -> "FEEDER".equals(device.kind()) || "WATERER".equals(device.kind());
            case "TARE" -> "SCALE".equals(device.kind());
            default -> false;
        };
        if (!supported) throw new ApiException(HttpStatus.BAD_REQUEST, "该设备不支持此指令");
        if ("DISPENSE".equals(input.commandType())) {
            Object amount = input.payload().get("amount");
            if (!(amount instanceof Number number) || number.doubleValue() <= 0
                || number.doubleValue() > 5000) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "出粮或出水量须在 0 到 5000 之间");
            }
        }
        try {
            String payloadJson = json.writeValueAsString(input.payload());
            long id = mapper.createCommand(workspaceId, deviceId, input.commandType(),
                payloadJson, UUID.randomUUID().toString());
            mapper.applyCommand(workspaceId, id);
            return id;
        } catch (JsonProcessingException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "指令参数无效");
        }
    }

    public List<DeviceMapper.Command> commands(AppPrincipal user, long workspaceId, long deviceId) {
        get(user, workspaceId, deviceId);
        return mapper.commands(workspaceId, deviceId);
    }
}
