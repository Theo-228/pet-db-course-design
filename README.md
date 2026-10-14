# 宠物智能管理平台｜数据库课程设计

本仓库用于 ChatGPT 与官方 Codex 之间传递项目资料、进行数据库课程设计开发；GitHub 上的文档和聊天记录是**静态快照**，新聊天不会自动同步。

## 建议的阅读顺序

1. [项目背景与最新范围](docs/PROJECT_CONTEXT.md)
2. [已确认设计决策](docs/DECISIONS.md)
3. [Codex 接手说明](docs/CODEX_ENTRY.md)
4. **[ChatGPT 原始讨论全文](docs/chat-history/2026-10-14-pet-platform-discussion.md)**

## 当前交付目标

完整的前后端分离数据库课程设计，四大模块为：
- 宠物管理（含 AI 健康分析接口）
- 智能设备管理
- 智能自动化中心
- 全局 AI 智能助手（仅接口）

**全部 AI 功能仅预留接口，不实现模型或知识库。** 家庭与猫咖共用一套系统，不开发商业运营功能。数据库建模、查询、事务及可运行的前后端是本阶段重点。

技术选型建议：Java 21、Spring Boot 3.5.x、MyBatis、PostgreSQL 17、Vue 3、Vite、Element Plus；版本兼容性应在初始化项目时再确认。

原始讨论前半段涉及未来商业产品的广泛设想，**以讨论后半段最新的明确要求为当前开发范围**。详情见上述原始文件。
