# claude-chinese-pack

Windows x64 的 Claude Desktop 离线打包工具，以及 Claude Code、Cowork VM 的可选安装辅助工具。

**这是非官方构建工具，不是 Claude 源码，也不是汉化补丁。** 项目不修改官方 MSIX，不绕过登录、订阅、地区限制或 Windows 虚拟化要求，与 Anthropic 无隶属关系。

仓库只提供脚本、启动器源码与测试，不包含官方安装文件、图标、VM 镜像、凭据或用户数据。项目名称中的 `chinese` 指中文文档及部分安装界面，不代表修改 Claude 的界面语言。

## 环境

- Windows x64；构建使用 Windows PowerShell 5.1 或 PowerShell 7。
- Windows 自带的 .NET Framework C# 编译器：`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`。
- 可访问官方发布源的网络；下载和代码签名验证可能需要联网。
- 从可信官方渠道获取的 `Claude Setup.exe`，通过 `-SetupPath` 指定。
- Cowork 另需本机已经验证的、未包含用户状态的 VM 资源；项目不自动配置虚拟化。

新构建默认写入已被 Git 忽略的 `releases/`。请在测试机验证后再分发；本仓库的自动测试不代表真实 VM 启动或安装兼容性认证。

## Desktop 离线包

```powershell
.\scripts\build-claude-offline.ps1 -SetupPath 'C:\inputs\Claude Setup.exe'
```

脚本查询官方 Windows x64 最新 MSIX 地址，验证 Setup/MSIX 的 Authenticode 签名，检查 MSIX 内部版本和架构，然后生成：

```text
releases/
  Claude-Desktop-<version>.exe
  Claude-Desktop-<version>.exe.sha256
  Claude-Desktop-Offline-<release>-x64/
    Claude Setup.exe
    Claude-x64.msix
    Install-Claude.cmd
    Install-Claude.ps1
    BUILD-INFO.json
    SHA256SUMS.txt
    ...
```

EXE 是本项目编译的非官方包装器，默认没有代码签名；其中的官方组件仍保留原签名。图标在本地从已验证的 MSIX 中提取，不随源码发布；可用 `-IconPath` 指定自己有权使用的 ICO。

双击 EXE 后，由官方 Setup 的 `-local-msix` 参数执行安装。不要直接运行 MSIX。以目标 Windows 用户启动安装器，官方 Setup 会请求所需的提权。

## 加入 Claude Code

先获取官方原生 Windows x64 Code 文件，再构建：

```powershell
.\scripts\get-claude-code.ps1 -Version latest
.\scripts\build-claude-offline.ps1 -SetupPath 'C:\inputs\Claude Setup.exe' `
    -IncludeCode -RuntimeRoot '.\build-runtime'
```

下载脚本验证官方清单的 SHA-256、大小、签名和文件版本，仅写入构建目录，不安装 Code，不读取账号数据。也可以指定明确版本。

`-IncludeCode` 只选择 `RuntimeRoot` 中版本号最高且签名有效的 Code，**不会自动更新该目录**。每次要追随最新 Code 时，先运行下载脚本。构建记录保存实际使用的 Desktop/Code 版本。

EXE 内含 Setup、MSIX、Code 三项，Code 安装位置为：

```text
%LOCALAPPDATA%\Claude-3p\claude-code\<version>\claude.exe
```

这是 Desktop 使用的资源目录，不会注册全局 `claude` 命令。只需目录而不需 EXE 时使用 `-NoExe`；单独的 `-IncludeCode` 不支持 `-NoExe`。

## Cowork 一键补丁

```powershell
.\scripts\build-cowork-patch.ps1 -CreateInstaller
```

默认读取 `%LOCALAPPDATA%\Claude-3p\vm_bundles\claudevm.bundle`。也可用 `-Source` 指定可信资源目录，用 `-Output` 指定新补丁目录。

这会生成原始补丁目录，以及相邻的 `*-Installer/`：

```text
Install-Cowork-VM.exe
<patch-name>.zip
SHA256SUMS.txt
README.txt
...
```

**给最终用户分发整个 `*-Installer` 目录。EXE 和 ZIP 必须放在一起。** 用户退出 Claude 后，双击 EXE，点击“安装”；不需要操作 CMD 或手动解压。VM 不嵌入单个 EXE。

如果已有由当前源码生成的补丁目录，可以单独压缩及编译：

```powershell
.\scripts\build-cowork-installer.ps1 -PatchDirectory 'C:\releases\Cowork-VM-Patch-example'
```

可传入 `-IconPath`；未指定时使用系统默认程序图标，不依赖仓库外的私有文件。

安装器检查 ZIP 内嵌预期哈希、逐文件哈希、磁盘空间和 Claude 进程。现有 VM 被重命名为备份，发现 `sessiondata.vhdx` 时拒绝覆盖。备份不会自动删除，详细失败日志写入安装用户的临时目录。

VM 是本机资源快照，**不保证为官方最新版本**。只收集以下 7 个文件：

```text
initrd          initrd.zst
rootfs.vhdx     rootfs.vhdx.zst
smol-bin.vhdx
vmlinuz        vmlinuz.zst
```

文件名白名单不会检查镜像内部内容。构建者仍需确认来源可信且镜像未写入用户数据。未知文件、账号目录、会话盘、来源和修复标记不会被复制。

## 完整离线目录

```powershell
.\scripts\build-claude-offline.ps1 -SetupPath 'C:\inputs\Claude Setup.exe' -IncludeRuntime
```

该模式包含 Desktop、Code 和独立 `payload` VM。以同一个目标 Windows 用户运行目录中的 `Install-Claude.cmd`，它会转交完整安装脚本。生成的单 EXE **不包含 VM**，不能替代完整目录。

## 开发与验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
pwsh.exe -NoProfile -File .\tests\Run-Tests.ps1
```

测试使用小型合成资源，不下载、安装或启动 Claude，不读取真实 VM。CI 在 Windows 上检查两种 PowerShell、C# 编译、资源解包、校验失败处理及备份保护。

目录结构：

```text
scripts/             构建与下载入口
  install/           随产物分发的安装脚本
  lib/               共享打包函数
src/                 C# 启动器
tests/               无真实安装的自动测试
.github/             CI 与 PR 模板
build-runtime/       本地构建输入，不提交
releases/            本地构建产物，不提交
  archive/           历史构建物
  desktop/           已交付的 Desktop 包
  cowork/            已交付的 Cowork 包
  intermediate/      待清理的过程文件
```

根目录只保留 README、AGENTS 与工具配置。构建产物和本地缓存不要提交。

贡献前运行两种 PowerShell 下的测试，检查 `git diff --check` 和暂存区。修改安装路径、校验、提权或覆盖逻辑时补充失败路径测试。不要提交官方二进制、图标、日志、用户数据、凭据，也不要用 Git LFS 绕过限制。

安全问题请通过维护者的私密联系渠道报告，不在公开 Issue 或 PR 上传敏感文件。只提供脱敏信息与最小复现步骤。

## 限制与发布

- `-ReuseMsix -Force` 可复用同输出目录中的 MSIX，仍重新校验签名、内部版本及架构；不允许复用已有完整 runtime 目录。
- 官方接口、资源目录和文件格式可能变化，变化时应失败并人工检查，不能跳过验证。
- 哈希证明文件未变，不证明分发者可信。应通过可信渠道取得安装器并检查包装器签名。
- 不保证位级可复现：官方 `latest`、签名验证环境、编译器和时间戳会影响结果。复核版本来源可查 `BUILD-INFO.json`。
- 本项目不自动发布官方二进制文件。公开源码不等于获得第三方文件、图标或商标的再分发授权。

## 许可与第三方说明

以下 MIT 许可证只适用于本项目原创脚本、启动器和文档。Claude Desktop、Claude Setup、Claude Code、Cowork VM 和官方图标不属于本项目作品，不由本项目重新授权。相关名称仅用于说明兼容目标，不表示官方背书；分发者需自行确认第三方资源的使用及分发权限。

### MIT License

Copyright (c) 2026 claude-chinese-pack contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
