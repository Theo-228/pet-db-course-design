package com.petos.automation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.petos.auth.AccessService;
import com.petos.auth.AppPrincipal;
import com.petos.common.ApiException;
import com.petos.device.DeviceMapper;
import com.petos.measurement.MeasurementMapper;
import com.petos.pet.PetMapper;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class AutomationServiceTest {
    private final AccessService access = mock(AccessService.class);
    private final AutomationMapper rules = mock(AutomationMapper.class);
    private final MeasurementMapper metrics = mock(MeasurementMapper.class);
    private final DeviceMapper devices = mock(DeviceMapper.class);
    private final PetMapper pets = mock(PetMapper.class);
    private final AppPrincipal user = new AppPrincipal(1, "tester");
    private AutomationService service;

    @BeforeEach
    void setUp() {
        service = new AutomationService(access, rules, metrics, devices, pets,
            new ObjectMapper());
        when(metrics.metrics()).thenReturn(List.of(
            new MeasurementMapper.Metric("weight_kg", "体重", "kg", "PET", false)));
    }

    @Test
    void createsAlertRuleWithExplicitWorkspace() {
        when(rules.create(anyLong(), any(), any(), any(), any(), isNull(), isNull(),
            any(), isNull(), any(), any(), anyInt())).thenReturn(42L);
        AutomationController.RuleInput input = new AutomationController.RuleInput(
            "Weight alert", "weight_kg", "GT", new BigDecimal("6.0"),
            null, null, "ALERT", null, Map.of(), "WARNING", 300);
        assertEquals(42L, service.create(user, 7, input));
        verify(access).write(user, 7);
        verify(rules).create(7, "Weight alert", "weight_kg", "GT",
            new BigDecimal("6.0"), null, null, "ALERT", null, "{}", "WARNING", 300);
    }

    @Test
    void rejectsIncompatibleDeviceCommandBeforeInsert() {
        when(devices.find(7, 3)).thenReturn(new DeviceMapper.Device(
            3, 7, null, "feeder-3", "Feeder", "FEEDER", "DEDICATED", "ONLINE",
            null, null));
        AutomationController.RuleInput input = new AutomationController.RuleInput(
            "Wrong tare", "weight_kg", "GT", new BigDecimal("6.0"),
            null, null, "DEVICE_COMMAND", 3L,
            Map.of("command_type", "TARE"), "WARNING", 0);
        ApiException ex = assertThrows(ApiException.class,
            () -> service.create(user, 7, input));
        assertEquals(HttpStatus.BAD_REQUEST, ex.status());
    }
}
