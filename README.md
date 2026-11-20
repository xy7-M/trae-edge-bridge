# TRAE 浏览器插件 · Edge 适配补丁

让 **TRAE 官方浏览器插件（Trae Work 浏览器插件）在 Microsoft Edge 中正常工作** 的最小配置补丁。

> 本仓库**不包含** TRAE 官方扩展的任何源码。扩展本体由 TRAE（北京引力弹弓科技有限公司）提供并拥有版权，本项目只提供 native messaging 清单与安装脚本。

---

## 使用特点

| 特点 | 说明 |
|---|---|
| **双浏览器共存** | Edge 与 Chrome 各用一份独立的 native messaging 清单，互不干扰。一个浏览器出问题不会连带另一个 |
| **零源码改动** | 不修改、不反编译扩展本体的任何 `.js` 文件。只写入注册表指针和 JSON 清单 |
| **纯用户级改动** | 仅写 `HKCU`（当前用户）注册表，不碰 `HKLM` 系统级、不碰程序目录、不碰防火墙 |
| **一条命令安装** | `install.ps1` 自动探测 TRAE 安装路径、生成清单、写注册表并自检 |
| **一条命令回滚** | `uninstall.ps1` 删除注册表键与生成的清单，恢复到安装前状态 |
| **保留原有配置** | 不会覆盖 TRAE 自带的 `com.solo.browser_bridge.json`，只新增旁路清单 |
| **全程本地通信** | 桥接进程仅监听 `127.0.0.1`，不产生任何外网连接 |

---

## 它解决什么问题

TRAE 的浏览器插件通过 **Chrome native messaging** 与本机桥接程序通信。在 Edge 中会出现两类问题：

### 问题 1：扩展被 Edge 拒绝加载

`manifest.json` 的 `externally_connectable.matches` 中若出现 IP 通配符（如 `http://192.168.*:*/*`），
Chrome / Edge 会在加载时直接报错：

```
Invalid match pattern 'http://192.168.*:*/*'
```

**原因**：`*` 通配符只适用于 DNS 域名，不适用于 IP 地址。

**修正**：改用精确的 origin，或收窄为具体域名。

```json
"externally_connectable": {
  "matches": [
    "https://*.bytedance.net/*",
    "https://*.trae.cn/*",
    "http://localhost:*/*",
    "http://127.0.0.1:*/*"
  ]
}
```

> ⚠️ 不要用 `http://*/*` 兜底。那等于允许**任意 http 网站**调用扩展的全部自动化工具（点击、填表、截图、执行脚本），是真实的浏览器接管风险。

### 问题 2：连上就断（Connected → Disconnected 循环）

扩展控制台反复打印：

```
[NativeBridge] Connected to native host
[NativeBridge] Disconnected: Specified native messaging host not found.
```

**原因**：Chrome 与 Edge 共用同一份 native messaging 清单，浏览器重启后握手失败。

**修正**：为两个浏览器各准备一份独立清单，并在注册表中分别指向。

---

## 安装

### 前置条件

1. 已安装 TRAE，且扩展目录存在：
   `%USERPROFILE%\.trae-cn\plugins\extension`
2. 已安装桥接程序：
   `%USERPROFILE%\.trae-cn\plugins\browser-bridge\browser-bridge.exe`
3. Edge 中已通过「加载解压缩的扩展」加载该扩展

### 执行

```powershell
# 默认同时配置 Edge 和 Chrome
powershell -ExecutionPolicy Bypass -File .\install.ps1

# 只配置 Edge
powershell -ExecutionPolicy Bypass -File .\install.ps1 -EdgeOnly

# 只配置 Chrome
powershell -ExecutionPolicy Bypass -File .\install.ps1 -ChromeOnly
```

安装完成后：

1. 打开 `edge://extensions/`
2. 找到 **Trae Work 浏览器插件**，点「重新加载」
3. 点击工具栏扩展图标，确认显示 **已连接**

### 验证

```powershell
# 桥接进程应存在，且仅监听 127.0.0.1
Get-Process browser-bridge
Get-NetTCPConnection -OwningProcess (Get-Process browser-bridge).Id
```

---

## 卸载 / 回滚

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

会删除：

- `HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.solo.browser_bridge`
- `HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.solo.browser_bridge`
- 本脚本生成的 `com.solo.browser_bridge.edge.json` / `.chrome.json`

不会删除 TRAE 自带的原始清单与桥接程序。

---

## 安全说明

审计结论如下，供你判断是否要在自己的机器上运行。

### 本补丁做了什么

- 写入 2 个注册表键（`HKCU`，当前用户级）
- 生成 2 个 JSON 清单文件（位于 TRAE 插件目录内）
- 不执行任何网络请求，不下载任何文件

### 官方扩展的审计结果

| 检查项 | 结果 |
|---|---|
| `fetch` / `XMLHttpRequest` / `WebSocket` | 0 处 |
| `chrome.cookies` / `history` / `bookmarks` / `downloads` | 0 处 |
| `document.cookie` / `localStorage` / `chrome.storage` | 0 处 |
| `eval` / `new Function` / 混淆字符串 | 0 处 |
| `content_scripts` 注入 | 无 |
| `host_permissions` 声明 | 无 |
| 自启动 / 计划任务 / 服务 | 无 |

### 桥接程序

| 项 | 结果 |
|---|---|
| 数字签名 | 有效（北京引力弹弓科技有限公司 / DigiCert） |
| 监听地址 | 仅 `127.0.0.1:19234` |
| 出站连接 | 无 |
| 子进程 | 无 |

### 必须知道的固有权限

这些是浏览器自动化功能的**必要代价**，不是缺陷：

1. **`debugger` 权限** —— 附着标签页时可读取页面内容、模拟点击与输入。附着期间浏览器顶部会显示「正在调试此浏览器」提示条。
2. **`upload_file` 能力** —— 可将指定本地文件填入网页的文件上传框，需调用方明确提供路径。
3. **`externally_connectable` 通道** —— `*.bytedance.net`、`*.trae.cn`、`localhost` 下的页面可以调用扩展工具。若这些域名被 XSS 攻破，攻击者可借道控制浏览器。想彻底消除可删除 manifest 中的 `externally_connectable` 整段，但可能影响 TRAE 网页端集成。
4. **风险边界在调用方** —— 谁能操作你的 TRAE 会话，谁就能操作浏览器。扩展本身不会自发执行动作。

---

## 常见问题

**Q：安装后弹窗仍显示「未连接」？**
A：先确认 `browser-bridge.exe` 在运行；再在 `edge://extensions/` 点「重新加载」；如果仍失败，点卡片上的「服务工作进程」→ 打开 DevTools 控制台看具体报错。

**Q：桥接进程起来了但马上又消失？**
A：说明两份清单指向了同一个文件或注册表未生效。运行 `install.ps1` 后重启浏览器。

**Q：Chrome 那边会不会被弄坏？**
A：不会。Chrome 使用独立的 `.chrome.json`，内容与原清单等价，可随时用 `uninstall.ps1` 回滚。

**Q：TRAE 更新了扩展怎么办？**
A：扩展 ID 由 manifest 中的 `key` 固定，更新后 ID 不变，本补丁继续有效。若 ID 变化，用 `-ExtensionId` 参数重新安装。

---

## 许可

本仓库的脚本与文档以 MIT 协议发布。
TRAE 扩展本体、桥接程序的版权归北京引力弹弓科技有限公司所有，不在本仓库范围内。
