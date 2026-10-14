# 数据库使用说明

需要 PostgreSQL 17、`psql` 和允许创建 `btree_gist` 扩展的账号。建议为开发创建一个空数据库，例如 `petos_dev`。生产部署应由迁移工具按版本执行 `migrations/` 中的脚本；不要对已有数据库重新运行旧迁移。

在项目根目录运行：

```powershell
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V1__core_schema.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V2__metric_catalog.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V3__reporting_views.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V4__integrity_guards.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V5__measurement_semantics.sql
psql -X -v ON_ERROR_STOP=1 -1 -d petos_dev -f database/migrations/V6__access_foundation.sql
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
- 自动化规则仅支持确定性单指标阈值。业务服务应在同一事务内创建 `automation_execution` 与对应的 `alert_event` 或 `device_command`，并通过唯一约束保证同一规则对同一测量只执行一次。
- AI 不在数据库内生成预测、诊断或问答内容。

完整实体关系、关键约束、尚待后端实现的事务边界见 [docs/database-design.md](../docs/database-design.md)。
