<#
.SYNOPSIS
    撤销 Edge 适配补丁，恢复到安装前状态。

.DESCRIPTION
    删除本补丁写入的注册表键与生成的清单文件。
    不会删除 TRAE 自带的原始清单与桥接程序。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "TRAE 浏览器插件 · Edge 适配补丁 —— 卸载" -ForegroundColor Cyan
Write-Host "================================================"
Write-Host ""

$bridgeDir = Join-Path $env:USERPROFILE '.trae-cn\plugins\browser-bridge'

# ---------- 1. 删除注册表键 ----------
Write-Host "[1/2] 删除注册表键"

$keys = @(
    'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.solo.browser_bridge',
    'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.solo.browser_bridge'
)

foreach ($k in $keys) {
    if (Test-Path $k) {
        try {
            Remove-Item -Path $k -Recurse -Force
            Write-Ok "已删除: $k"
        } catch {
            Write-Warn "删除失败: $k —— $($_.Exception.Message)"
        }
    } else {
        Write-Warn "不存在（跳过）: $k"
    }
}

# ---------- 2. 删除生成的清单 ----------
Write-Host ""
Write-Host "[2/2] 删除生成的清单文件"

$files = @(
    (Join-Path $bridgeDir 'com.solo.browser_bridge.edge.json'),
    (Join-Path $bridgeDir 'com.solo.browser_bridge.chrome.json')
)

foreach ($f in $files) {
    if (Test-Path $f) {
        try {
            Remove-Item -Path $f -Force
            Write-Ok "已删除: $f"
        } catch {
            Write-Warn "删除失败: $f —— $($_.Exception.Message)"
        }
    } else {
        Write-Warn "不存在（跳过）: $f"
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "如需彻底恢复，请在浏览器扩展页移除「Trae Work 浏览器插件」，" -ForegroundColor DarkGray
Write-Host "或重新运行 TRAE 的插件安装流程。" -ForegroundColor DarkGray
Write-Host ""
