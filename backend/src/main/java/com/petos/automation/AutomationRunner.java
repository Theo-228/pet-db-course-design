package com.petos.automation;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.petos.device.DeviceMapper;
import com.petos.measurement.MeasurementService;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.transaction.support.TransactionTemplate;

@Component
public class AutomationRunner {
    private static final Logger log = LoggerFactory.getLogger(AutomationRunner.class);
    private final AutomationMapper mapper;
    private final DeviceMapper devices;
    private final ObjectMapper json;
    private final TransactionTemplate transaction;

    public AutomationRunner(AutomationMapper mapper, DeviceMapper devices, ObjectMapper json,
                            PlatformTransactionManager manager) {
        this.mapper = mapper; this.devices = devices; this.json = json;
        this.transaction = new TransactionTemplate(manager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onMeasurement(MeasurementService.Recorded event) {
        process(event.workspaceId(), event.measurementId());
    }

    @Scheduled(initialDelay = 10000, fixedDelay = 30000)
    public void replayPending() {
        for (AutomationMapper.Dispatch dispatch : mapper.pendingBatch()) {
            process(dispatch.workspaceId(), dispatch.measurementId());
        }
    }

    private void process(long workspaceId, long measurementId) {
        if (mapper.pending(workspaceId, measurementId) == null) return;
        List<AutomationMapper.Rule> matches;
        try {
            matches = mapper.matches(workspaceId, measurementId);
        } catch (Exception ex) {
            mapper.failDispatch(workspaceId, measurementId, "无法读取规则");
            log.error("Cannot inspect rules for measurement {}", measurementId, ex);
            return;
        }
        boolean failed = false;
        for (AutomationMapper.Rule rule : matches) {
            try {
                transaction.executeWithoutResult(status ->
                    run(new MeasurementService.Recorded(workspaceId, measurementId), rule));
            } catch (Exception ex) {
                failed = true;
                log.error("Rule {} failed for measurement {}", rule.id(), measurementId, ex);
            }
        }
        if (failed) mapper.failDispatch(workspaceId, measurementId, "至少一条规则执行失败；等待重试");
        else mapper.completeDispatch(workspaceId, measurementId);
    }

    private void run(MeasurementService.Recorded event, AutomationMapper.Rule rule) {
        long workspaceId = event.workspaceId();
        Long executionId = mapper.begin(workspaceId, rule.id(), event.measurementId(), rule.actionKind());
        if (executionId == null) return;
        if ("ALERT".equals(rule.actionKind())) {
            mapper.alert(workspaceId, executionId, event.measurementId(), rule.severity(),
                rule.name(), "测量值触发规则：" + rule.metricCode() + " " + rule.comparator()
                    + " " + rule.threshold());
            mapper.finish(workspaceId, executionId, "SUCCEEDED", null);
            return;
        }
        if (!"ONLINE".equals(mapper.deviceStatus(workspaceId, rule.targetDeviceId()))) {
            mapper.finish(workspaceId, executionId, "FAILED", "目标设备离线，未执行模拟指令");
            return;
        }
        try {
            JsonNode payload = json.readTree(rule.actionPayload());
            String commandType = payload.path("command_type").asText();
            long commandId = mapper.command(workspaceId, rule.targetDeviceId(), executionId,
                commandType, rule.actionPayload(), "automation-" + executionId);
            devices.applyCommand(workspaceId, commandId);
            mapper.finish(workspaceId, executionId, "SUCCEEDED", null);
        } catch (Exception ex) {
            log.warn("Cannot apply simulated command for execution {}", executionId, ex);
            mapper.finish(workspaceId, executionId, "FAILED", "模拟指令执行失败");
        }
    }
}
