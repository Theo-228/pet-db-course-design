# Windows 本机运行指南

本指南对应 2026-11-25 已实际运行的环境。以下命令使用 PowerShell，路径含空格时请加引号。首次配置完成后，日常使用只需执行启动脚本。

## 1. 本机环境与端口

| 项目 | 当前配置 |
|---|---|
| 项目目录 | `D:\3upupup\Database\pet-db-course-design-main` |
| JDK | `D:\JDK21`，Java 21.0.6 |
| Maven | `D:\dev\apache-maven-3.9.10\bin\mvn.cmd` |
| PostgreSQL | `D:\pgsql\bin`，17.6 |
| Node.js | `D:\Nodejs`，22.17.0 |
| 前端 | `http://127.0.0.1:5173/` |
| 后端 | `http://127.0.0.1:18080/` |
| 数据库 | `127.0.0.1:15432`，库名和开发账号均为 `petos` |
| 独立数据库文件 | 项目下 `.local\pgdata` |
| Maven 依赖缓存 | 项目下 `.local\m2` |

前后端和数据库均仅监听本机。独立开发库采用本机 trust 认证；它没有配置数据库密码，仅供这台电脑开发演示。不要改成对外监听。它与电脑上原有的其他数据库目录分开。

`start-local.ps1`、`stop-local.ps1` 当前使用上表中的工具路径；换电脑时需要相应调整。项目自身默认端口仍为后端 8080、数据库 5432，本指南通过环境变量改为 18080 和 15432。

## 2. 日常启动与停止

```powershell
Set-Location 'D:\3upupup\Database\pet-db-course-design-main'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-local.ps1
Start-Process 'http://127.0.0.1:5173/'
```

脚本依次检查/启动独立 PostgreSQL、后台后端和 Vite 前端，日志写入 `.local`。首次启动后端通常还需等待数秒。检查接口就绪：

```powershell
Invoke-RestMethod 'http://127.0.0.1:5173/api/auth/csrf'
```

返回含 `headerName`、`token` 的 JSON 表示前端代理和后端已连通。浏览器登录或注册后即可操作。已有账号和演示数据保存在本机数据库中，刷新页面不会清除。

停止本项目的前后端与独立数据库：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stop-local.ps1
```

停止不会删除数据。这两个脚本不是 Windows 系统服务，也没有配置开机自启。

## 3. 首次下载与安装依赖

当前电脑已经完成本节和下一节，**不要重复初始化现有数据库目录**。换目录或换电脑时才按实际情况执行。

```powershell
Set-Location 'D:\3upupup\Database'
git clone https://github.com/Theo-228/pet-db-course-design.git
Set-Location .\pet-db-course-design
git switch feat/history-visualization-local-run

$env:JAVA_HOME = 'D:\JDK21'
$env:Path = "$env:JAVA_HOME\bin;D:\Nodejs;D:\pgsql\bin;$env:Path"
java -version
node --version
& 'D:\pgsql\bin\postgres.exe' --version

New-Item -ItemType Directory -Force .local | Out-Null
Push-Location frontend
npm.cmd ci --cache ..\.local\npm-cache
Pop-Location
```

这里使用 `npm.cmd` 避免 PowerShell 对 `npm.ps1` 的执行策略限制。依赖使用仓库的 `package-lock.json`。

## 4. 首次创建独立开发数据库

在项目根目录执行。先确认 `.local\pgdata` 不存在；现有数据应继续使用，不能用 `initdb` 覆盖。

```powershell
if (Test-Path '.local\pgdata') {
    throw '已有数据库目录，请跳过初始化，直接启动现有数据库。'
}
& 'D:\pgsql\bin\initdb.exe' -D '.local\pgdata' -U petos --auth=trust --encoding=UTF8 --locale=C
if ($LASTEXITCODE -ne 0) { throw '数据库初始化失败' }

& 'D:\pgsql\bin\pg_ctl.exe' -D '.local\pgdata' -l '.local\postgres.log' -o '-p 15432 -h 127.0.0.1' -w start
if ($LASTEXITCODE -ne 0) { throw '数据库启动失败' }

& 'D:\pgsql\bin\createdb.exe' -h 127.0.0.1 -p 15432 -U petos petos
```

只创建空数据库即可。首次后端启动时，Flyway 自动执行 `database/migrations/V1…V7`；不要先手动执行迁移 SQL。迁移历史显式存放在 `public`，避免开发账号 `petos` 与业务 schema 同名时重启找错位置。

## 5. 构建或修改后重新运行

Java 后端运行时会占用 JAR 文件，**重新打包前先停止**。前端开发服务器支持热更新，但生产构建仍应单独验证。

```powershell
Set-Location 'D:\3upupup\Database\pet-db-course-design-main'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stop-local.ps1

$env:JAVA_HOME = 'D:\JDK21'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

& 'D:\dev\apache-maven-3.9.10\bin\mvn.cmd' `
  '-Dmaven.repo.local=D:\3upupup\Database\pet-db-course-design-main\.local\m2' `
  -f backend\pom.xml package -B -ntp
if ($LASTEXITCODE -ne 0) { throw '后端构建失败，请先查看 Maven 错误' }

Push-Location frontend
npm.cmd run build
if ($LASTEXITCODE -ne 0) { throw '前端构建失败' }
node src\history.test.js
Pop-Location

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-local.ps1
```

`package` 会运行现有后端单元测试。已下载依赖且希望离线构建时，可在 Maven 参数中加 `-o`。换项目路径时也要同步修改 `-Dmaven.repo.local` 的路径。没有本机 Maven 时，可以改用仓库包装器：

```powershell
.\backend\mvnw.cmd -f backend\pom.xml package -B -ntp
```

包装器首次执行需要联网下载 Maven。`npm run build` 产生的 `dist` 不由当前启动脚本提供；当前启动脚本运行的是 Vite 开发服务器。

## 6. 手动前台运行（排查问题时）

数据库已经启动后，在第一个 PowerShell 终端执行：

```powershell
Set-Location 'D:\3upupup\Database\pet-db-course-design-main'
$env:PETOS_DB_URL = 'jdbc:postgresql://127.0.0.1:15432/petos'
$env:PETOS_DB_USER = 'petos'
$env:PETOS_DB_PASSWORD = ''
$env:PETOS_PORT = '18080'
& 'D:\JDK21\bin\java.exe' -jar backend\target\petos-backend-0.1.0.jar --server.address=127.0.0.1
```

在第二个终端启动前端：

```powershell
Set-Location 'D:\3upupup\Database\pet-db-course-design-main\frontend'
$env:PETOS_API_TARGET = 'http://127.0.0.1:18080'
npm.cmd run dev -- --port 5173 --strictPort
```

前台运行用 `Ctrl+C` 停止。不要同时启动后台脚本和手动前台进程，否则会争用端口；手动启动的进程也不会写入脚本维护的 PID 文件。

## 7. 验证与日志

后端启动并就绪后，执行真实 API 冒烟测试。Windows PowerShell 5 读取无 BOM 的中文 UTF-8 脚本时需要显式指定编码：

```powershell
Set-Location 'D:\3upupup\Database\pet-db-course-design-main'
& ([scriptblock]::Create([IO.File]::ReadAllText(
    (Join-Path $PWD 'backend\scripts\smoke.ps1'),
    [Text.Encoding]::UTF8
))) -BaseUrl 'http://127.0.0.1:5173'
```

成功时打印 `PASS workspace=...`。该测试会在开发库内保留随机命名的测试账号和工作空间。

数据库约束测试使用事务，完成后回滚：

```powershell
& 'D:\pgsql\bin\psql.exe' -X -v ON_ERROR_STOP=1 `
  -h 127.0.0.1 -p 15432 -U petos -d petos `
  -f database\tests\schema_test.sql
```

日志查看：

```powershell
Get-Content .local\backend.log -Tail 60
Get-Content .local\backend.err.log -Tail 60
Get-Content .local\frontend.log -Tail 40
Get-Content .local\frontend.err.log -Tail 40
Get-Content .local\postgres.log -Tail 40
```

检查端口和数据库状态：

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -in 5173,18080,15432 |
  Select-Object LocalAddress,LocalPort,OwningProcess
& 'D:\pgsql\bin\pg_ctl.exe' -D '.local\pgdata' status
```

`JAR` 重命名失败通常是后端仍在运行；先停止后再构建。页面打开但 API 失败时，检查后端日志及 `PETOS_API_TARGET`，后端刚启动时也需等待就绪。首次构建缺依赖时需要联网；若代理指向不可用地址，应在当前终端修正代理设置后重试，不必更改全局配置。

## 8. 历史图表与本机演示数据

宠物列表点击“数据趋势”，设备列表点击“历史数据”，可跳转到列表下方的面板。支持选择对象、指标、近 7/30/90 天、自选日期和按天/周统计。

体重等读数展示阶段均值，活动/进食/饮水展示累计量；来源环形图按记录条数统计。缺失日期不补零。接口按完整日期范围聚合，不受最近 200 条列表上限影响。

当前本机已为指定演示账号准备 3 只宠物、8 台模拟设备、90 天共 1,818 条测量、9 条健康记录、4 条规则、4 条告警和 2 次模拟设备联动。所有示例均标注为演示数据。账号密码不记录在仓库；AI 仍是 501 占位，设备动作仍为模拟。

**GitHub 保存源码，不会自动同步数据库内容。** `.local`（数据库、日志、缓存、截图、临时导入工具）、`node_modules`、`target` 和 `dist` 均不提交。换电脑克隆代码后需要重新准备开发数据，不能假定演示账号已存在。

## 9. 已完成的验证

- 后端打包和现有 2 项单元测试通过。
- 前端生产构建和 3 项历史统计计算测试通过。
- PostgreSQL 约束测试和原有 API 冒烟测试通过。
- 历史接口验证了超过 200 条记录的完整汇总、日期限制及跨空间拒绝。
- Edge 浏览器验证了桌面/手机布局、图表显示及周统计切换。
