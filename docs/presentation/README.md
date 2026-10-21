# PetOS 汇报与学习材料

这份目录供数据库课程汇报和从零理解项目使用。

- [15 页项目与数据库设计 PPT](PetOS-database-presentation.pptx)：课堂展示用，前 3 页介绍项目，其余页面重点讲数据库。
- [数据库零基础讲解](database-walkthrough.md)：按一条测量数据解释表之间的关系、约束、自动化和常见答辩问题。网页端 AI 应先读这份文字，再对照 PPT 和 SQL。

项目的实际实现以迁移脚本和代码为准。建议的阅读顺序是：

1. [零基础讲解](database-walkthrough.md)
2. [数据库设计基线](../database-design.md)
3. [V1–V7 迁移脚本](../../database/migrations/)
4. [应用设计与接口](../application-design.md)
5. PPT 和 [课程报告草稿](../course-report.md)

可以把下面这段直接发给网页端 AI：

> 请先阅读 `docs/presentation/database-walkthrough.md`、`docs/database-design.md` 和 `database/migrations/`，再结合 `docs/presentation/PetOS-database-presentation.pptx` 逐页教我。我是数据库初学者。每次只讲一页：先用生活中的例子解释，再指出对应的表、主键/外键/约束和 SQL 文件，最后问我一个简单问题，等我回答后再继续。请区分已实现、模拟实现和未来计划；不要把 AI 占位接口、模拟设备指令或未经验证的性能描述成真实能力。如果文档和迁移脚本不一致，以最新迁移后的实际结构为准，并说明差异。
