<#
.SYNOPSIS
    为 TRAE 官方浏览器插件安装 Edge / Chrome 双浏览器 native messaging 清单。

.DESCRIPTION
    只做三件事：
      1. 在 TRAE 插件目录生成 Edge / Chrome 各自的 native messaging 清单
      2. 写入当前用户（HKCU）注册表指针
      3. 自检并输出结果

    不修改扩展源码、不修改系统级注册表、不执行任何网络请求。

.PARAMETER ExtensionId
    扩展 ID，默认值对应 TRAE 官方插件（由 manifest 中的 key 固定，版本升级后不变）。

.PARAMETER EdgeOnly
    只配置 Edge。

.PARAMETER ChromeOnly
    只配置 Chrome。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -EdgeOnly
#>
[CmdletBinding()]
param(
    [string]$ExtensionId = 'nbmnklcgnddbjafigmlhfjhefcfcgggn',
    [switch]$EdgeOnly,
    [switch]$ChromeOnly
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "  $msg" }
function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "TRAE 浏览器插件 · Edge 适配补丁" -ForegroundColor Cyan
Write-Host "================================================"
Write-Host ""

# ---------- 1. 定位 TRAE 目录 ----------
Write-Host "[1/5] 定位 TRAE 插件目录"

$traeRoot     = Join-Path $env:USERPROFILE '.trae-cn\plugins'
$extensionDir = Join-Path $traeRoot 'extension'
$bridgeDir    = Join-Path $traeRoot 'browser-bridge'
$bridgeExe    = Join-Path $bridgeDir 'browser-bridge.exe'

if (-not (Test-Path $extensionDir)) {
    Write-Fail "未找到扩展目录: $extensionDir"
    Write-Host "       请先安装 TRAE 并确认插件已下载。" -ForegroundColor DarkGray
    exit 1
}
Write-Ok "扩展目录: $extensionDir"

if (-not (Test-Path $bridgeExe)) {
    Write-Fail "未找到桥接程序: $bridgeExe"
    Write-Host "       请先安装 TRAE 并确认 browser-bridge 已就绪。" -ForegroundColor DarkGray
    exit 1
}
Write-Ok "桥接程序: $bridgeExe"

# ---------- 2. 校验扩展 ID ----------
Write-Host ""
Write-Host "[2/5] 校验扩展 ID"

$manifestPath = Join-Path $extensionDir 'manifest.json'
if (Test-Path $manifestPath) {
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.key) {
            # 由公钥推导扩展 ID：SHA256 -> 前 16 字节 -> a-p 编码
            $der = [Convert]::FromBase64String($manifest.key)
            $sha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($der)
            $id = -join ($sha[0..15] | ForEach-Object {
                [char](97 + ($_ -shr 4))
                [char](97 + ($_ -band 0x0F))
            })
            if ($id -ne $ExtensionId) {
                Write-Warn "manifest.key 推导出的 ID 为 $id，与期望的 $ExtensionId 不同"
                Write-Warn "将使用推导值。若确有变化，请核对后重试。"
                $ExtensionId = $id
            } else {
                Write-Ok "扩展 ID 校验通过: $ExtensionId"
            }
        } else {
            Write-Warn "manifest.json 中无 key 字段，使用默认 ID: $ExtensionId"
        }
    } catch {
        Write-Warn "无法解析 manifest.json，使用默认 ID: $ExtensionId"
    }
} else {
    Write-Warn "未找到 manifest.json，使用默认 ID: $ExtensionId"
}

# ---------- 3. 生成清单 ----------
Write-Host ""
Write-Host "[3/5] 生成 native messaging 清单"

$templatePath = Join-Path $PSScriptRoot 'manifests\com.solo.browser_bridge.edge.template.json'
if (-not (Test-Path $templatePath)) {
    Write-Fail "模板文件缺失: $templatePath"
    exit 1
}
$template = Get-Content $templatePath -Raw
$content  = $template.Replace('__BRIDGE_EXE__', $bridgeExe).Replace('__EXTENSION_ID__', $ExtensionId)

$targets = @()

if (-not $ChromeOnly) {
    $edgeManifest = Join-Path $bridgeDir 'com.solo.browser_bridge.edge.json'
    Set-Content -Path $edgeManifest -Value $content -Encoding UTF8
    Write-Ok "Edge 清单: $edgeManifest"
    $targets += [pscustomobject]@{
        Browser = 'Edge'
        RegKey  = 'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\com.solo.browser_bridge'
        Path    = $edgeManifest
    }
}

if (-not $EdgeOnly) {
    $chromeManifest = Join-Path $bridgeDir 'com.solo.browser_bridge.chrome.json'
    Set-Content -Path $chromeManifest -Value $content -Encoding UTF8
    Write-Ok "Chrome 清单: $chromeManifest"
    $targets += [pscustomobject]@{
        Browser = 'Chrome'
        RegKey  = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.solo.browser_bridge'
        Path    = $chromeManifest
    }
}

# ---------- 4. 写注册表 ----------
Write-Host ""
Write-Host "[4/5] 写入当前用户注册表（HKCU）"

foreach ($t in $targets) {
    try {
        if (-not (Test-Path $t.RegKey)) {
            New-Item -Path $t.RegKey -Force | Out-Null
        }
        Set-ItemProperty -Path $t.RegKey -Name '(default)' -Value $t.Path
        $readback = (Get-ItemProperty -Path $t.RegKey).'(default)'
        if ($readback -eq $t.Path) {
            Write-Ok "$($t.Browser): $readback"
        } else {
            Write-Fail "$($t.Browser) 注册表写入校验失败"
        }
    } catch {
        Write-Fail "$($t.Browser) 注册表写入失败: $($_.Exception.Message)"
    }
}

# ---------- 5. 自检 ----------
Write-Host ""
Write-Host "[5/5] 自检"

$origManifest = Join-Path $bridgeDir 'com.solo.browser_bridge.json'
if (Test-Path $origManifest) {
    Write-Ok "TRAE 原始清单保留未动"
} else {
    Write-Warn "未发现 TRAE 原始清单（可能为全新安装，可忽略）"
}

$proc = Get-Process -Name browser-bridge -ErrorAction SilentlyContinue
if ($proc) {
    Write-Ok "桥接进程运行中 (PID: $($proc.Id -join ','))"
    $conn = Get-NetTCPConnection -OwningProcess $proc.Id -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Listen' }
    if ($conn) {
        foreach ($c in $conn) { Write-Ok ("监听: {0}:{1}" -f $c.LocalAddress, $c.LocalPort) }
    }
} else {
    Write-Warn "桥接进程未运行（打开浏览器并激活扩展后会自动拉起）"
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "下一步:" -ForegroundColor Cyan
Write-Host "  1. 打开 edge://extensions/（或 chrome://extensions/）"
Write-Host "  2. 找到「Trae Work 浏览器插件」，点「重新加载」"
Write-Host "  3. 点击工具栏扩展图标，确认显示「已连接」"
Write-Host ""
Write-Host "回滚: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1" -ForegroundColor DarkGray
Write-Host ""
