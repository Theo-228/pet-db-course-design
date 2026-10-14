package com.petos.pet;

import com.petos.auth.AccessService;
import com.petos.auth.AppPrincipal;
import com.petos.common.ApiException;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PetService {
    public record Report(PetMapper.LatestWeight latestWeight,
                         List<PetMapper.DailyTotal> dailyTotals) {}
    private final AccessService access;
    private final PetMapper mapper;

    public PetService(AccessService access, PetMapper mapper) {
        this.access = access;
        this.mapper = mapper;
    }

    public List<PetMapper.Pet> list(AppPrincipal user, long workspaceId) {
        access.read(user, workspaceId);
        return mapper.list(workspaceId);
    }

    public PetMapper.Pet get(AppPrincipal user, long workspaceId, long petId) {
        access.read(user, workspaceId);
        PetMapper.Pet pet = mapper.find(workspaceId, petId);
        if (pet == null) throw new ApiException(HttpStatus.NOT_FOUND, "宠物不存在");
        return pet;
    }

    @Transactional
    public long create(AppPrincipal user, long workspaceId, PetController.PetInput input) {
        access.write(user, workspaceId);
        return mapper.create(workspaceId, input.name().trim(), input.species().trim(),
            input.breed(), input.sex(), input.birthDate());
    }

    @Transactional
    public void update(AppPrincipal user, long workspaceId, long petId, PetController.PetInput input) {
        access.write(user, workspaceId);
        if (mapper.update(workspaceId, petId, input.name().trim(), input.species().trim(),
            input.breed(), input.sex(), input.birthDate(), input.status()) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "宠物不存在或已归档");
        }
    }

    @Transactional
    public void retire(AppPrincipal user, long workspaceId, long petId) {
        access.write(user, workspaceId);
        if (mapper.retire(workspaceId, petId) == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "宠物不存在或已归档");
        }
    }

    public List<PetMapper.HealthRecord> healthRecords(AppPrincipal user, long workspaceId, long petId) {
        get(user, workspaceId, petId);
        return mapper.healthRecords(workspaceId, petId);
    }

    public Report report(AppPrincipal user, long workspaceId, long petId) {
        get(user, workspaceId, petId);
        return new Report(mapper.latestWeight(workspaceId, petId),
            mapper.dailyTotals(workspaceId, petId));
    }

    @Transactional
    public long addHealthRecord(AppPrincipal user, long workspaceId, long petId,
                                PetController.HealthInput input) {
        access.write(user, workspaceId);
        get(user, workspaceId, petId);
        return mapper.addHealthRecord(workspaceId, petId, input.kind(), input.occurredAt(),
            input.note().trim());
    }
}
