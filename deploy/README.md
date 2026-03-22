# private_network 分支部署说明

这个分支为 nanobot 增加了**基于白名单的私有网络访问策略**，用于让 `exec`、`web_fetch` 和子代理工具链按配置访问局域网 / 内网地址。

## 配置项

在你的 `config.json` 的 `tools` 下增加：

```json
{
  "tools": {
    "networkSecurity": {
      "allowPrivateNetwork": false,
      "allowedPrivateCidrs": ["192.168.31.0/24"],
      "allowedPrivateHosts": ["localhost"]
    }
  }
}
```

## 行为说明

- 公网 URL 保持原有行为。
- 私有 / 内网 URL 默认仍然被拦截。
- 只有满足以下条件之一时才允许访问：
  - 命中 `allowedPrivateCidrs`
  - 命中 `allowedPrivateHosts`
  - `allowPrivateNetwork: true`（全开，不推荐）

## 影响范围

- `exec`
- `web_fetch`
- subagent tool execution

## deploy 目录内容

- `switch_to_private_network.ps1`：Windows 部署 / 服务重装脚本
- `install_private_network_linux.sh`：Linux 用户级 systemd 服务脚本
- `install_private_network_macos.sh`：macOS 用户级 launchd 服务脚本

这些脚本都采用同一个更稳妥的安装流程：

1. 从本地源码构建 wheel
2. 卸载当前 `uv tool` 安装的 `nanobot-ai`
3. 从刚构建出来的 wheel 安装
4. 运行一次 `gateway --config ...` 冒烟测试
5. 写入或更新服务配置
6. 重启服务并检查状态

之所以改成先构建 wheel 再安装，是因为直接对本地目录执行 `uv tool install <repo-path>` 时，实际遇到过安装内容未完全刷新的情况；而显式安装 freshly built wheel 更稳定。

## Windows 用法

```powershell
powershell -ExecutionPolicy Bypass -File D:\storage\nanobot\deploy\switch_to_private_network.ps1
```

可选参数：

- `-ServiceName nanobot-gateway`
- `-RepoPath D:\storage\nanobot`
- `-ConfigPath C:\Users\admin\.nanobot\config.json`
- `-SkipServiceRestart`

## Linux 用法

建议先给脚本执行权限：

```bash
chmod +x deploy/install_private_network_linux.sh
```

然后执行：

```bash
REPO_PATH="$HOME/storage/nanobot" \
CONFIG_PATH="$HOME/.nanobot/config.json" \
bash deploy/install_private_network_linux.sh
```

默认写入用户级 systemd 服务：

- `~/.config/systemd/user/nanobot-gateway.service`

常用查看命令：

```bash
systemctl --user status nanobot-gateway
journalctl --user -u nanobot-gateway -f
```

## macOS 用法

建议先给脚本执行权限：

```bash
chmod +x deploy/install_private_network_macos.sh
```

然后执行：

```bash
REPO_PATH="$HOME/storage/nanobot" \
CONFIG_PATH="$HOME/.nanobot/config.json" \
bash deploy/install_private_network_macos.sh
```

默认写入用户级 LaunchAgent：

- `~/Library/LaunchAgents/nanobot-gateway.plist`

常用查看命令：

```bash
launchctl print gui/$(id -u)/nanobot-gateway
```

日志默认在：

- `~/.nanobot/service-logs/`
