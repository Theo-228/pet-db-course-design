# PetOS · 宠物健康与智能设备工作台

面向数据库课程设计的前后端分离应用。家庭与猫咖使用同一套工作空间模型：宠物、区域、设备、测量、自动化规则与提醒。项目重点是可验证的关系设计、完整性约束、历史数据、SQL 统计和业务事务，而不是商业运营或虚构的 AI 能力。

## 已实现

| 领域 | 可运行功能 |
|---|---|
| 账号与工作空间 | 注册/登录、Session + CSRF、工作空间隔离、OWNER/EDITOR/VIEWER 权限基础 |
| 宠物 | 档案、归档、健康记录、最新体重与近 30 天活动/饮食统计 |
| 设备 | 设备/区域、状态、专属及共享绑定、模拟控制指令 |
| 测量 | 人工/设备上报、事件去重、设备能力校验、不可变原始记录、追加式归属修订 |
| 自动化 | 阈值规则、冷却、告警与模拟设备联动、执行日志、持久化待处理队列与重试 |
| AI | 健康分析、行为识别、助手、数据库问答、自动化决策的接口占位；均明确返回 501 |

不包含真实硬件驱动、大模型、知识库、会员、订单、收费或门店经营模块。设备指令在数据库中模拟为 `APPLIED`，**不代表真实硬件已经动作**。

## 技术与目录

- PostgreSQL 17；Flyway 顺序迁移位于 `database/migrations/`。
- Java 21、Spring Boot 3.5.16、MyBatis Starter 3.0.5；`backend/`。
- Vue 3、Vite 7、Element Plus、Axios；`frontend/`。
- E-R 图、约束说明和课程设计材料位于 `docs/`；原始聊天记录也在其中。

## 本地启动

需要 JDK 21、PostgreSQL 17、Node.js 24（或符合 Vite 7 要求的版本）和 npm。初次运行先创建一个**空数据库**及可使用 `btree_gist` 扩展的账号；Flyway 会自动建表，不要先手动执行迁移文件。

PowerShell 示例（替换连接信息）：

```powershell
$env:PETOS_DB_URL = 'jdbc:postgresql://127.0.0.1:5432/petos'
$env:PETOS_DB_USER = 'petos'
$env:PETOS_DB_PASSWORD = 'your-password'
./backend/mvnw.cmd -f backend/pom.xml spring-boot:run
```

另开终端启动前端：

```powershell
cd frontend
npm ci
npm run dev
```

打开 `http://127.0.0.1:5173/`，注册账号后即可创建工作空间。后端默认监听 8080；如果端口占用，设定 `PETOS_PORT`，并在前端启动前设定 `PETOS_API_TARGET`（例如 `http://127.0.0.1:18080`）。

## 验证与演示

```powershell
./backend/mvnw.cmd -f backend/pom.xml test package
cd frontend
npm run build
```

在运行中的后端上执行 `backend/scripts/smoke.ps1`，会在当前数据库创建带随机后缀的测试工作空间，验证宠物/设备/绑定、测量归属、阈值提醒、模拟命令、共享设备的未知身份与修订、事件去重、SQL 健康统计以及跨工作空间拒绝。测试数据会留在该数据库；建议使用独立的开发库。数据库级约束测试见 `database/README.md`，其 SQL 使用事务并在末尾回滚。

推荐演示流程：注册 → 添加宠物和区域 → 注册专属体重秤并模拟上线 → 绑定宠物 → 创建体重阈值提醒 → 模拟设备上报 → 查看自动归属、执行日志与告警 → 改用共享设备上报并确认其默认未知归属 → 手动追加归属修订 → 查看宠物健康统计。AI 页面只展示未接入状态。

## 文档

- [项目边界与历史决定](docs/PROJECT_CONTEXT.md)
- [应用设计与 API](docs/application-design.md)
- [数据库设计与 E-R 图](docs/database-design.md)
- [数据库运行和测试](database/README.md)
- [课程设计报告草稿](docs/course-report.md)

教师 PPT 原件和最终评分细则尚未进入仓库，因此课程报告是可核验的项目文档草稿，而不是对未知评分条款的承诺。
