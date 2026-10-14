# 数据库使用说明

需要 PostgreSQL 17、`psql` 和允许创建 `btree_gist` 扩展的账号。**运行应用时使用一个空数据库，让后端 Flyway 自动执行全部迁移。**下面的手动命令只用于独立的数据库实验库；手动迁移过的数据库不能直接交给未建立历史记录的 Flyway 使用。

在项目根目录运行：

```powershell
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V1__core_schema.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V2__metric_catalog.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V3__reporting_views.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V4__integrity_guards.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V5__measurement_semantics.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V6__access_foundation.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V7__automation_dispatch.sql
psql -X -v ON_ERROR_STOP=1 -d petos_dev -f database/tests/schema_test.sql
```

`schema_test.sql` 在事务内创建测试数据并回滚，不留下记录。可选演示数据：

```powershell
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/demo/seed.sql
psql -X -d petos_dev -f database/queries/demo_queries.sql
```

演示数据只应在空的开发数据库运行一次。脚本使用预置的指标目录，不依赖真实设备。

## 模型约定

- 所有业务记录属于一个 `workspace`。家庭与猫咖使用相同的表和约束，通过空间、宠物和设备数量体现规模差异。
- `device_pet_binding` 记录关联有效期。共享设备允许同时关联多只宠物；专属设备的有效期不能交叠。
- `measurement` 是不可变的原始事实。共享设备无法识别使用者时，测量仍然保存，但没有宠物归属。
- `measurement_attribution` 保存可追加的归属判断与修正。最新一条为当前判断，旧判断可追溯；仅有设备关联不等于完成身份识别。
- 自动化规则仅支持确定性单指标阈值。测量写入触发器在同一事务内产生 `automation_dispatch` 待处理行；后端在提交后处理并定时重试。单次执行事务同时写入 `automation_execution` 与对应的 `alert_event` 或 `device_command`，唯一约束避免重复动作。冷却判定以测量记录时间为准。
- AI 不在数据库内生成预测、诊断或问答内容。

完整实体关系和关键约束见 [docs/database-design.md](../docs/database-design.md)。演示数据使用真实表，不包含账号；如果与应用一起使用，演示库中的测量行会进入待处理队列。
