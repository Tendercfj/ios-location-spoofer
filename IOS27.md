# iOS 27 定位修改说明

## 结论

iOS 27 beta6 及以后版本、iOS 27 正式版无法继续使用 `ios-location-spoofer.sgmodule` 修改定位。

该模块必须先由 Shadowrocket 解密 Apple 定位服务的 HTTPS 响应，再把 `/clls/wloc` 中的坐标交给 `location-spoofer.js` 改写。新系统会在脚本运行前拒绝用户 CA（certificate pinning），并且不再形成 Shadowrocket 可见的 `/clls/wloc` 响应。因此下面这些操作都不能解决：

- 重新安装或完全信任 Shadowrocket CA；
- 添加 `gspe*` / `gsp*`、`*.apple.com` 等域名；
- 修改 URL 正则或 protobuf JavaScript；
- 关闭 QUIC、切换 Surge/Loon/Quantumult X/Stash；
- 反复关开定位或重启设备。

项目曾尝试扩展 Apple Host 池，但新 Host 同样在 TLS 握手阶段断开，反而导致系统无法定位，所以没有保留该改动。iOS 27 上应先关闭 Shadowrocket 模块。

## 可用替代：CoreDevice/DVT

仓库提供 [ios27-location-spoofer.sh](ios27-location-spoofer.sh)，通过 Apple 的 DVT `LocationSimulation` 服务设置位置，不拦截 WLOC 网络流量。脚本要求 `pymobiledevice3` 11.15.4 或更高版本；使用 `uvx` 时固定为 11.15.4。该版本包含 iOS 27 和 iOS 27.2 的 tunnel 适配。

这条路径需要：

- 一台 Mac 和 USB 数据线（脚本也可在配置好 USB 驱动的 Linux 上运行）；
- iPhone 解锁并选择“信任这台电脑”；
- 在 iPhone 的“设置 → 隐私与安全性 → Developer Mode”中开启开发者模式并按提示重启；
- `uvx`（推荐，`brew install uv`）或已安装的 `pymobiledevice3`。

### 1. 查看设备

```bash
./ios27-location-spoofer.sh devices
```

如果连接了多台设备，记下目标设备的 UDID，后续命令末尾加 `--udid <UDID>`。

### 2. 首次准备

```bash
./ios27-location-spoofer.sh prepare
```

这会检查 USB 设备和 Developer Mode，并挂载匹配系统版本的 DeveloperDiskImage。设备每次重启后应重新执行一次。首次运行 `uvx` 会下载固定版本的 `pymobiledevice3`，之后使用本地缓存。

### 3. 设置位置

```bash
./ios27-location-spoofer.sh set 39.9087 116.3975
```

参数顺序是纬度、经度。命令通过 CoreDevice/RSD tunnel 访问 DVT `LocationSimulation`，并保持前台会话；请保持终端窗口和 USB 连接，按 `Ctrl+C` 结束并恢复真实定位。若会话异常中断，再执行下面的 `clear`。

### 4. 恢复真实位置

```bash
./ios27-location-spoofer.sh clear
```

如果设置位置时使用了 `--udid`，`clear` 也应传同一个 UDID。

## 排查

- `No device connected`：解锁 iPhone、重新插线并在手机上点“信任”。
- DVT / `InvalidService` 错误：确认 Developer Mode 已开启并重启手机，再执行 `prepare`。
- 多台设备时选错：先运行 `devices`，再给 `prepare`、`set`、`clear` 加 `--udid`。
- 地图位置没有变化：保持 `set` 进程运行，彻底退出并重开地图 App；部分 App 会检测 `isSimulatedBySoftware` 并拒绝模拟位置。
- 结束后位置未恢复：重新连接设备并执行 `clear`，必要时重启 iPhone。

## 依据

- 项目 PR #71 明确记录 iOS 27 beta6 的定位 Host certificate pinning，扩 Host 会握手失败：<https://github.com/mekos2772/ios-location-spoofer/pull/71>
- Issue #79 记录 beta7 不再产生可处理的 `/clls/wloc` 响应：<https://github.com/mekos2772/ios-location-spoofer/issues/79>
- 正式版复现：<https://github.com/mekos2772/ios-location-spoofer/issues/84>、<https://github.com/mekos2772/ios-location-spoofer/issues/87>
- `pymobiledevice3` iOS 17+ tunnel 与 DVT 文档：<https://doronz88.github.io/pymobiledevice3/guides/ios17-tunnels/>、<https://doronz88.github.io/pymobiledevice3/guides/cli-recipes/#dvt-examples>

## 限制

这不是免电脑方案。DVT 模拟位置可能被 App 识别，USB 或 DVT 会话中断后也可能失效。截至 2026-09-18，没有经过验证的纯 Shadowrocket 绕过方式。当前测试环境没有连接 iOS 27 真机，因此只验证了脚本、参数和命令接口，尚未完成真机端到端 `set` / `clear` 验证。
