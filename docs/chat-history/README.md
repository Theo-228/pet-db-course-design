# ChatGPT 原始聊天导出存放位置

把 ChatGPT Exporter 导出的**宠物管理平台相关对话 Markdown** 文件放在本目录。例如：

- `2026-10-14-pet-platform-discussion.md`

如导出结果包含图片或附件，并且正文依赖相对路径，可保留原目录结构（包括 `images/`、`files/`）。若扩展生成 ZIP，请先在本地解压，再将 Markdown 和必要资源上传到 GitHub；**不要只把 ZIP 传进仓库**，否则 Codex 无法像读取普通 Markdown 一样直接索引正文。

导出操作参考：<https://github.com/thekester/chatgpt-export>

推荐在扩展里选 **This conversation → Markdown**，只导出与本项目有关的对话。不要选择任何“导出后删除对话”的功能。上传 GitHub 前检查是否包含账号、令牌、个人资料等不宜公开的信息。课程仓库初期建议设为 **Private**。

本目录中的 Markdown 是独立快照，不是自动实时同步。每次产生值得传递给 Codex 的新讨论，都需要重新导出并提交到 GitHub。
