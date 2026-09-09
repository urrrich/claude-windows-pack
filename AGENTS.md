# 项目维护约定

## 范围与安全边界

本项目是非官方 Windows x64 离线打包工具，远程为 `git@github.com:teamo-lab/claude-chinese-pack.git`。

- 只维护原创脚本、启动器、文档和测试，不修改官方 MSIX，不实现汉化、认证或订阅绕过。
- 禁止打包凭据、Cookie、聊天记录、session、缓存或整个用户目录。
- 官方 EXE、MSIX、Code、VM、图标不提交 Git，也不使用 Git LFS 变相提交。
- MIT 只适用于原创源码与文档，不代表拥有第三方资源再分发权。
- 不自动上传二进制包、不擅自更改仓库可见性、不强推远程已有历史。

## 目录布局

```text
scripts/              构建、下载入口
scripts/install/      安装脚本与 CMD，构建时复制到产物目录
scripts/lib/          共享打包函数
src/                  C# 启动器
tests/                自动测试
.github/              Windows CI 与 PR 模板
build-runtime/        本地输入和资源缓存，Git 忽略
releases/             所有构建产物，Git 忽略
releases/archive/     历史版本
releases/desktop/     已交付 Desktop 包
releases/cowork/      已交付 Cowork 包
releases/intermediate/ 待清理过程文件
```

根目录只放 `README.md`、本文件与工具配置，不新增散落脚本、图标、压缩包。许可、贡献和第三方说明统一维护在 README，不再拆出 LICENSE、CONTRIBUTING、SECURITY 或 THIRD_PARTY_NOTICES。变更目录时同步修改 README、测试、CI 和脚本间调用。

## 构建命令

在仓库根目录运行；Setup 必须来自可信官方渠道：

```powershell
# Desktop：Setup + MSIX
.\scripts\build-claude-offline.ps1 -SetupPath 'C:\inputs\Claude Setup.exe'

# 更新构建用 Code，再生成 Desktop + Code 单 EXE
.\scripts\get-claude-code.ps1 -Version latest
.\scripts\build-claude-offline.ps1 -SetupPath 'C:\inputs\Claude Setup.exe' `
    -IncludeCode -RuntimeRoot '.\build-runtime'

# 完整目录：使用本机已验证的 Code 和 Cowork VM
.\scripts\build-claude-offline.ps1 -SetupPath 'C:\inputs\Claude Setup.exe' -IncludeRuntime

# Cowork：图形安装器 EXE + ZIP，不要求用户操作 CMD
.\scripts\build-cowork-patch.ps1 -CreateInstaller
```

`-IncludeCode` 选取 RuntimeRoot 中数值版本最高的 Code，不自动联网更新 Code。用户要求“最新”时必须分别核实 Desktop 官方 MSIX 重定向和 Code 原生下载源；不得把本机版本当成官方最新版。

`-ReuseMsix -Force` 只复用已下载文件，不跳过签名、内部版本或架构校验。已有完整 runtime 输出目录不能覆盖复用，必须另指定输出目录，避免混入旧资源。

## 打包与安装约束

- 构建时验证 Setup、MSIX 和 Code 的 Authenticode；下载 Code 还验证上游 SHA-256、大小及文件版本。
- Code 只复制 `claude.exe`；VM 只复制 `scripts/lib/Packaging.Common.ps1` 中的 7 个文件，不递归拷贝整个来源目录。
- VM 是可信本机资源快照，不宣称为官方最新版本。白名单不能证明镜像内部无用户数据，来源确认不可省略。
- 文件操作使用 `-LiteralPath`；避免 junction、符号链接和越界路径；哈希或签名失败立即停止。
- 图标从已验证 MSIX 本地提取，或由 `-IconPath` 指定；不将官方图片、ICO 放进源码。
- 单 EXE 只嵌入 Desktop 和可选 Code。GB 级 VM 随 `payload` 或独立 ZIP 分发，EXE 与 ZIP 需放在一起。
- Desktop 必须通过官方 Setup 的 `-local-msix` 安装，不直接运行下载的 MSIX。
- 以目标 Windows 用户启动安装器，由 Setup 请求提权；不要切换到另一个管理员账号安装用户级 runtime。
- Code 目标为 `%LOCALAPPDATA%\Claude-3p\claude-code\<version>`，VM 目标为 `vm_bundles\claudevm.bundle`。
- VM 安装前要求 Claude 退出；已有会话盘时停止；已有 VM 保留备份，不直接覆盖或删除用户状态。
- 发布包的源码更新不会自动改变旧 EXE；需要明确重建并更新 SHA-256，不能声称旧包已经包含新修复。

## 测试与发布前检查

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
pwsh.exe -NoProfile -File .\tests\Run-Tests.ps1
git diff --check
git diff --cached --stat
```

测试只使用 `releases/` 内合成小文件和隔离的 LocalAppData。禁止向真实用户目录安装测试资源，也不能为了测试关闭用户 Claude、卸载 AppX 或删除 `%LOCALAPPDATA%\Claude-3p`。

真实安装、VM 启动、提权及官方 Setup 兼容性只能在专用测试机验证；未验证时在结果中如实说明。

暂存和推送前检查秘密、第三方内容、二进制、大文件和用户绝对路径。不要使用 `git add -f` 绕过忽略规则。

## 清理与迁移

先列出目标并核对解析后的绝对路径位于本仓库，再做删除或移动。重复产物只有哈希一致且保留副本明确时才能删除。历史包和已交付文件优先归档，未经明确授权不删除。

删除被环境阻止时，不换工具规避；将允许移动的过程文件归入 `releases/intermediate/`，并如实报告尚未删除。不要把归档说成释放了磁盘空间。
