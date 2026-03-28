# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## 常用命令

### 安装 / 开发环境
```bash
# pip
python3 -m pip install -e ".[dev]"

# uv（推荐，更快）
uv run --extra dev pytest
```

项目本身不依赖 uv（无 uv.lock），但 uv 可作为 pip 的替代用于开发和测试。不要改动 pyproject.toml 中的依赖声明。

### 运行 CLI
```bash
nanobot --help
nanobot onboard
nanobot onboard --wizard
nanobot agent -m "Hello!"
nanobot agent
nanobot gateway
nanobot status
```

### 常用子命令
```bash
nanobot channels status
nanobot channels login whatsapp
nanobot channels login weixin
nanobot provider login openai-codex
nanobot provider login github-copilot
```

### 格式化 / 静态检查
```bash
uv run --extra dev ruff check nanobot tests
uv run --extra dev ruff format nanobot tests
```

### 测试
```bash
uv run --extra dev pytest
uv run --extra dev pytest tests/agent/test_loop_cron_timezone.py
uv run --extra dev pytest tests/tools/test_web_fetch_security.py -k fetch
```

### 打包
```bash
uv run --extra dev python3 -m build
```

## 架构概览

- `nanobot/cli/commands.py` 是命令入口，`nanobot.cli.commands:app` 绑定到 `nanobot` 可执行文件。这里负责 `onboard`、`agent`、`gateway`、`status`、provider/channel 登录等流程编排。
- `nanobot/agent/loop.py` 是核心运行时。它把消息从 `MessageBus` 拉进来，构建上下文，调用模型，执行工具调用，保存会话，并驱动流式输出、cron、heartbeat 和 subagent。
- `nanobot/agent/context.py` 负责把历史、系统上下文、运行时信息、工具结果和多模态内容组装成模型输入。
- `nanobot/agent/memory.py` 负责会话记忆整理与压缩，避免上下文无限增长。
- `nanobot/agent/tools/` 是内置工具层：文件系统、shell、web search/fetch、message、spawn、cron、MCP 等工具都在这里注册并执行。
- `nanobot/agent/subagent.py` 负责后台子代理；它会用更受限的工具集合运行独立任务，并把结果回传给主消息流。
- `nanobot/bus/queue.py` 和 `nanobot/bus/events.py` 提供消息总线与 inbound/outbound 消息结构，CLI 和 channels 都通过它和 agent 解耦。
- `nanobot/channels/` 实现各聊天平台接入；`nanobot/channels/manager.py` 发现、初始化、启动、停止和转发这些 channel。
- `nanobot/providers/registry.py` 是模型提供方的单一注册表。provider 路由、环境变量、默认 base URL、OAuth/provider 类型判断都从这里派生。
- `nanobot/config/schema.py` 定义全局配置结构；`nanobot/config/loader.py` 负责加载/保存；`nanobot/config/paths.py` 负责 config、workspace、cron、history 等路径约定。
- `nanobot/cron/` 和 `nanobot/heartbeat/` 提供周期任务与唤醒式后台执行。
- `nanobot/session/manager.py` 管理持久会话历史，是 agent 记忆与多实例工作区的重要基础。

## 运行时与配置要点

- 默认配置文件在 `~/.nanobot/config.json`，默认 workspace 在 `~/.nanobot/workspace`。
- `agents.defaults.model` 决定默认模型；`agents.defaults.provider` 可强制 provider 路由，否则由注册表按模型名和配置自动匹配。
- `tools.restrictToWorkspace` 会把文件、shell 等工具限制在 workspace 内。
- `tools.exec.enable=false` 会直接不注册 shell 执行工具。
- `tools.networkSecurity` 控制可能访问内网/URL 的工具行为。
- `agents.defaults.timezone` 影响运行时上下文、heartbeat 和 cron 默认时区。

## 开发时最该先看的文件

- `nanobot/cli/commands.py`
- `nanobot/agent/loop.py`
- `nanobot/config/schema.py`
- `nanobot/providers/registry.py`
- `nanobot/channels/manager.py`

## 从上游 HKUDS 合并到 private_network

本仓库的 `private_network` 分支在 HKUDS/main 基础上增加了**私有网络安全**（`NetworkSecurityConfig`）功能。当需要从 HKUDS 合并新版本时，遵循以下冲突处理规则：

### 合并命令
```bash
git fetch HKUDS --tags
git merge v0.1.4.postX   # 替换为目标 tag
```

### 冲突处理原则

**1. 保留 private_network 分支的网络安全改动**

以下内容是本分支独有的，合入上游时必须保留，不能丢弃：

- `nanobot/config/schema.py` 中的 `NetworkSecurityConfig` 类定义
- `nanobot/config/schema.py` 中 `ToolsConfig.network_security` 字段
- `nanobot/security/network.py` 整个模块（URL 访问控制）
- `nanobot/agent/loop.py` 中 `network_security_config` 参数的传递（构造函数、`_register_default_tools`、`SubagentManager` 初始化）
- `nanobot/agent/subagent.py` 中 `network_security_config` 参数的存储和传递给 `ExecTool`/`WebFetchTool`
- `nanobot/agent/tools/shell.py` 和 `nanobot/agent/tools/web.py` 中 `network_security_config` 的接收和使用
- `nanobot/cli/commands.py` 中 `gateway()` 和 `agent()` 函数里 `network_security_config=config.tools.network_security` 的传参

**2. 吸收上游的结构性更新**

上游可能新增参数、重构类或引入新模块。这些应该全部合入，与本分支的网络安全改动并列：

- 新增的构造函数参数（如 `timezone`）——保留两边的参数，都传入
- 新增的类字段（如 `_start_time`、`_last_usage`、`self.runner`）——保留
- 新增的配置项（如 `exec_config.enable`）——保留，但对应的工具注册处要同时带上 `network_security_config`
- 版本号升级——合成 `X.Y.Z+private_network` 格式

**3. 版本号处理**

- `pyproject.toml` 中的 version 采用 `{上游版本}+private_network` 格式（如 `0.1.4.post6+private_network`）
- `nanobot/__init__.py` 中保留"从包元数据读取版本"的逻辑，仅更新 fallback 版本号

### 常见冲突场景与解法

| 冲突位置 | 解法 |
|----------|------|
| `nanobot/agent/loop.py` 构造函数参数 | 保留 `network_security_config` **和** 上游新增的参数（如 `timezone`），两者并列 |
| `nanobot/agent/loop.py` `_register_default_tools` | 保留 `exec_config.enable` 守卫，但 `ExecTool` 和 `WebFetchTool` 的参数里带上 `network_security_config` |
| `nanobot/agent/subagent.py` `__init__` | 保留 `self.network_security_config` **和** 上游新增的 `self.runner = AgentRunner(provider)` |
| `nanobot/cli/commands.py` `AgentLoop(...)` 调用 | 两处（`gateway` 和 `agent` 函数）都保留 `network_security_config=...` 和 `timezone=...` |
| `nanobot/config/schema.py` | 保留 `NetworkSecurityConfig` 类及其在 `ToolsConfig` 中的字段 |
| `pyproject.toml` version | 取上游版本号，追加 `+private_network` |
| `nanobot/__init__.py` | 保留从 `importlib.metadata` 读版本的逻辑，更新 fallback |

## 备注

- 项目使用 Python 3.11+。
- 测试配置在 `pyproject.toml` 中，pytest 会默认扫描 `tests/`。
- 代码风格由 Ruff 约束，行宽为 100。
- `private_network` 分支的 remote 是 `origin`（zrong/nanobot），上游 HKUDS/nanobot 是 `HKUDS` remote。
