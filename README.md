# Claude Windows Offline Pack

**Windows x64 · Desktop 离线安装 · Cowork VM 独立补丁**

[![Windows CI](https://github.com/urrrich/claude-windows-pack/actions/workflows/ci.yml/badge.svg)](https://github.com/urrrich/claude-windows-pack/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/urrrich/claude-windows-pack)](https://github.com/urrrich/claude-windows-pack/releases/latest)

将官方 Claude Desktop 安装资源封装为单个 EXE，并提供独立 Cowork VM 安装工具。中文安装说明、完整性校验和现有 VM 备份，让下载与部署过程更清晰。

> **非官方项目，与 Anthropic 无隶属关系。** 不修改官方 MSIX，不是汉化补丁，不绕过登录、订阅或其他服务限制。离线安装资源不代表 Claude 服务可以离线使用。

## 下载

本次构建日期：**2026-11-10**。版本号记录本次核实结果，不代表后续官方版本不会更新。

| 组件 | 版本 / 大小 | 下载渠道 |
| --- | --- | --- |
| Claude Desktop | `4.23118.1.0` · 532.49 MiB | **[下载安装器](https://github.com/urrrich/claude-windows-pack/releases/download/v4.23118.1.0/Claude-Desktop-4.23118.1.0.exe)** · [SHA-256](https://github.com/urrrich/claude-windows-pack/releases/download/v4.23118.1.0/Claude-Desktop-4.23118.1.0.exe.sha256) |
| Cowork VM 补丁 | `072b6cbfe74f…` · ZIP 约 2.95 GiB | **[百度网盘下载](https://pan.baidu.com/s/1vUgumghR7qDs-15IPNc2EA?pwd=vnxa)** · 提取码：`vnxa` |
| 构建信息与发布说明 | 安装范围、验证记录及限制 | [GitHub Release](https://github.com/urrrich/claude-windows-pack/releases/tag/v4.23118.1.0) |

**GitHub Release 不提供 VM 镜像或 VM 安装器。** VM 由维护者独立上传[百度网盘](https://pan.baidu.com/s/1vUgumghR7qDs-15IPNc2EA?pwd=vnxa)，提取码：`vnxa`。源码仓库只跟踪原创脚本、启动器、文档和测试，不提交官方二进制、镜像、图标或用户数据。

## 快速安装

### 1. 安装 Desktop

下载 `Claude-Desktop-4.23118.1.0.exe`，以实际使用 Claude 的 Windows 用户双击运行。包装器解出原始官方安装资源，并通过官方 Setup 的 `-local-msix` 参数安装；按官方 Setup 提示提权，不要切换到另一个管理员账号安装用户级资源。

本次 Desktop EXE 包含 **官方 Setup + MSIX**，不包含 Claude Code 原生运行时或 Cowork VM。

### 2. 按需安装 Cowork VM

从百度网盘下载以下两个文件，放在同一个文件夹，保留原文件名：

```text
Install-Cowork-VM.exe
Cowork-VM-072b6cbfe74f-20261110-x64.zip
```

完全退出 Claude 后，双击 `Install-Cowork-VM.exe` 并点击安装。无需手动解压或运行 CMD。安装器会核对完整 ZIP 和逐文件哈希；已有 VM 保留备份，检测到已有会话盘时停止覆盖。请为解压、安装暂存和已有备份留足磁盘空间。

### 3. 登录并检查运行条件

仍需有效 Claude 登录、相应功能权限与可访问服务的网络；Cowork 还需符合官方要求的 Windows 虚拟化环境。两包安装完成仅代表本次打包资源已部署，不能保证所有机器上功能立即可用。客户端可能继续下载 Code 或其他资源，也可能更新 VM。

## 完整性与验证范围

在下载目录运行 PowerShell：

```powershell
Get-FileHash -LiteralPath '.\Claude-Desktop-4.23118.1.0.exe' -Algorithm SHA256
```

本次 Desktop 安装器预期 SHA-256：

```text
43EB8DD354B89A39D270BDE80C77544847EC6B1549B75F2C8F26FA5AB2EBF607
```

VM 的校验清单和来源记录随网盘包提供。VM 版本为 `072b6cbfe74f428a98bd86035f83b322b369d1f1`，来自本次签名已验证的官方 Desktop 包所指定的清单（日期 `2026-10-22`），不宣称为独立核实的最新 VM。资源从官方地址全新下载，压缩文件和解压文件的大小与 SHA-256 均已核对；`smol-bin.vhdx` 来自同一官方 MSIX。

| 检查 | 本次结果 |
| --- | --- |
| 官方 Setup / MSIX 签名、MSIX 内部版本与架构 | 通过 |
| Desktop EXE 解包及嵌入文件哈希 | 通过 |
| VM 官方清单、实际 ZIP 全部文件及分卷拼接哈希 | 通过 |
| PowerShell 5.1 / PowerShell 7 自动测试 | 通过 |
| 真实机器安装、提权、官方 Setup 兼容性、Cowork VM 启动 | **尚未验证** |

本项目编译的包装器默认未签名，官方组件保留原始签名。哈希可检查文件完整性，不能替代对下载来源的信任判断。

---
## 从源码构建

- Windows x64；构建使用 Windows PowerShell 5.1 或 PowerShell 7。
- Windows 自带的 .NET Framework C# 编译器：`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`。
- 可访问官方发布源的网络；下载和代码签名验证可能需要联网。
- 从可信官方渠道获取的 `Claude Setup.exe`，通过 `-SetupPath` 指定。
- Cowork 另需来源已核实的干净 VM 资源，可从官方清单指定的地址获取，或使用已经验证且未包含用户状态的本机快照；项目不自动配置虚拟化。

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

**EXE 与 ZIP（或全部 ZIP 分卷）必须放在一起。** ZIP 超过 1,900,000,000 字节时，构建脚本自动生成 `.zip.001`、`.zip.002` 等分卷，可用于有单文件大小限制的分发渠道。本项目当前 VM 通过百度网盘分发，优先提供 EXE 与完整 ZIP，不重复提供分卷。安装器自动合并分卷并校验完整 ZIP 的 SHA-256，缺卷或损坏时停止。分卷安装还需额外预留一份 ZIP 的临时磁盘空间。 用户退出 Claude 后，双击 EXE，点击“安装”；不需要操作 CMD 或手动解压。VM 不嵌入单个 EXE。

如果已有由当前源码生成的补丁目录，可以单独压缩及编译：

```powershell
.\scripts\build-cowork-installer.ps1 -PatchDirectory 'C:\releases\Cowork-VM-Patch-example'
```

可传入 `-IconPath`；未指定时使用系统默认程序图标，不依赖仓库外的私有文件。

安装器检查 ZIP 内嵌预期哈希、逐文件哈希、磁盘空间和 Claude 进程。现有 VM 被重命名为备份，发现 `sessiondata.vhdx` 时拒绝覆盖。备份不会自动删除，详细失败日志写入安装用户的临时目录。

VM 可以来自官方清单指定的全新资源或可信本机快照，**不保证为官方最新版本**。只收集以下 7 个文件：

```text
initrd          initrd.zst
rootfs.vhdx     rootfs.vhdx.zst
smol-bin.vhdx
vmlinuz        vmlinuz.zst
```

文件名白名单不会检查镜像内部内容。构建者仍需确认来源可信且镜像未写入用户数据。未知文件、账号目录、会话盘、来源和修复标记不会被复制。

从签名已验证的官方 MSIX 提取 VM 清单并核实下载来源后，可向 `build-cowork-patch.ps1` 传入 `-OfficialVmManifest <清单路径>`。清单包含 `sha`、官方 x64 `baseUrl` 及 `files`（三个资源的压缩/解压大小和 SHA-256）。构建与安装均核对清单和实际资源；安装器仅在全部匹配时生成三个 `.origin` 版本标记，供客户端识别已预置资源。缺少此清单的旧式快照不生成标记，客户端可能重新下载 VM。

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
