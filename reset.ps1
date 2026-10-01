# reset.ps1 - WoTB_CN 一键回滚工具
# 合并自: hosts_reset.ps1 (电脑hosts) + del_dava.bat (PC登录缓存) + 模拟器hosts回滚 + wotblitz.exe.bak 恢复
# 由 reset.bat 提权调用; 直接运行时自动弹 UAC 提权。结果记录在本目录 reset_result.txt

$ErrorActionPreference = 'Continue'

# ---- 管理员自检: 非管理员自动提权重启 ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[i] 需要管理员权限, 弹出 UAC 窗口请点击[是]...'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
    } catch { Write-Host '[!] UAC 被取消, 未做任何修改.' }
    exit
}

$title = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  reset 会话'
$log = Join-Path $PSScriptRoot 'reset_result.txt'
Add-Content -Path $log -Value ('===== ' + $title + ' =====') -Encoding UTF8
function Log($m) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m)
    Write-Host $m
    Add-Content -Path $log -Value $line -Encoding UTF8
}

# ---- 1) 回滚电脑 hosts (移除本工具写入的劫持条目) ----
function Reset-PCHosts {
    $domains = @(
        'dl-wotblitz-gc.wargaming.net',
        'cdn.static.wotb.app',
        'cn1.plt.ms1shanghai.cn',
        'ma67.gdl.netease.com',
        'wotb-cn-launcher'
    )
    $hp = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    try {
        $lines = [System.IO.File]::ReadAllLines($hp)
        $keep = @($lines | Where-Object {
            $l = $_
            -not ($domains | Where-Object { $l -match [regex]::Escape($_) })
        })
        $removed = $lines.Count - $keep.Count
        if ($removed -eq 0) {
            Log '[1] 电脑 hosts 中没有本工具的劫持条目, 无需处理.'
        } else {
            $bak = "$hp.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $hp $bak
            $tmp = Join-Path $env:TEMP 'hosts.reset.tmp'
            [System.IO.File]::WriteAllLines($tmp, $keep)
            Copy-Item -Force $tmp $hp
            Remove-Item $tmp -ErrorAction SilentlyContinue
            Log ("[1] 已移除 {0} 行劫持条目, 备份: {1}" -f $removed, $bak)
        }
        ipconfig /flushdns | Out-Null
        Log '[1] DNS 缓存已刷新.'
    } catch {
        Log ("[1] 处理失败: " + $_)
    }
}

# ---- 2) 删除 WoTB PC 端登录缓存 (原 del_dava.bat) ----
function Reset-PCCache {
    if (Get-Process -Name 'wotblitz' -ErrorAction SilentlyContinue) {
        Log '[2] 检测到 wotblitz.exe 正在运行 — 请先退出游戏, 本次跳过清缓存.'
        return
    }
    $dirs = @(
        (Join-Path $env:LOCALAPPDATA 'wotblitz\DavaProject'),
        (Join-Path $env:LOCALAPPDATA 'wotblitz\packs'),
        (Join-Path $env:LOCALAPPDATA 'Packages\7458BE2C.WorldofTanksBlitz_x4tje2y229k00\LocalState\DAVAProject'),
        (Join-Path $env:LOCALAPPDATA 'Packages\7458BE2C.WorldofTanksBlitz_x4tje2y229k00\LocalState\packs')
    )
    $any = $false
    foreach ($d in $dirs) {
        if (Test-Path -LiteralPath $d) {
            $any = $true
            try {
                Remove-Item -LiteralPath $d -Recurse -Force
                Log ('[2] 已删除: ' + $d)
            } catch {
                Log ('[2] 删除失败: ' + $d + ' — ' + $_)
            }
        }
    }
    if (-not $any) { Log '[2] 未找到登录缓存目录 (可能已清过).' }
    Log '[2] 完成. PC 客户端下次启动会重建缓存 (首登一次 reason 12 属正常).'
}

# ---- adb 定位: config.json 的 mumu_dir > 常见安装路径 > 运行中的 MuMu 进程 > 手动粘贴 ----
function Find-ADB {
    $cfg = Join-Path $PSScriptRoot 'config.json'
    if (Test-Path $cfg) {
        try {
            $j = Get-Content $cfg -Raw | ConvertFrom-Json
            if ($j.mumu_dir) {
                foreach ($sub in @('nx_main\adb.exe', 'shell\adb.exe', 'adb.exe')) {
                    $p = Join-Path $j.mumu_dir $sub
                    if (Test-Path $p) { return $p }
                }
            }
        } catch {}
    }
    $rels = @(
        'MuMuPlayer\nx_main\adb.exe',
        'Program Files\Netease\MuMuPlayer-12.0\nx_main\adb.exe',
        'Program Files\Netease\MuMuPlayer\nx_main\adb.exe',
        'Program Files (x86)\Netease\MuMuPlayer-12.0\nx_main\adb.exe',
        'Netease\MuMuPlayer-12.0\nx_main\adb.exe',
        'Netease\MuMuPlayer\nx_main\adb.exe'
    )
    foreach ($drv in (Get-PSDrive -PSProvider FileSystem)) {
        foreach ($r in $rels) {
            $p = Join-Path $drv.Root $r
            if (Test-Path $p) { return $p }
        }
    }
    foreach ($proc in (Get-Process -Name 'MuMu*' -ErrorAction SilentlyContinue)) {
        if ($proc.Path) {
            foreach ($sub in @('adb.exe', '..\adb.exe')) {
                $p = Join-Path (Split-Path $proc.Path) $sub
                if (Test-Path $p) { return $p }
            }
        }
    }
    return $null
}

# ---- 3) 回滚模拟器 hosts (移除 cn1 劫持行) ----
function Reset-EmuHosts {
    $adb = Find-ADB
    if (-not $adb) {
        Log '[3] 未自动找到 adb (adb 随 MuMu 安装目录提供).'
        $in = Read-Host '    请粘贴 MuMu 安装目录 (例如 E:\MuMuPlayer, 回车跳过本项)'
        if ($in) {
            $in = $in.Trim('"').Trim()
            foreach ($sub in @('nx_main\adb.exe', 'shell\adb.exe', 'adb.exe')) {
                $p = Join-Path $in $sub
                if (Test-Path $p) { $adb = $p; break }
            }
        }
        if (-not $adb) { Log '[3] 仍无 adb, 跳过本项.'; return }
    }
    Log ('[3] adb: ' + $adb)
    & $adb start-server 2>$null | Out-Null

    $devs = @()
    foreach ($attempt in 1..2) {
        $devs = @()
        $out = (& $adb devices) -join "`n"
        foreach ($ln in ($out -split "`r?`n")) {
            $f = $ln.Trim() -split '\s+'
            if ($f.Count -ge 2 -and $f[1] -eq 'device') { $devs += $f[0] }
        }
        if ($devs.Count -gt 0) { break }
        foreach ($s in @('127.0.0.1:16384', '127.0.0.1:5555')) {
            & $adb connect $s | Out-Null
        }
    }
    if ($devs.Count -eq 0) {
        Log '[3] adb 未发现模拟器 — 请先启动 MuMu 模拟器后再执行本项.'
        return
    }
    $serial = $null
    foreach ($p in @('127.0.0.1:16384', '127.0.0.1:5555')) {
        if ($devs -contains $p) { $serial = $p; break }
    }
    if (-not $serial) {
        foreach ($d in $devs) { if ($d -like 'emulator-*') { $serial = $d; break } }
    }
    if (-not $serial) { $serial = $devs[0] }
    if ($devs.Count -gt 1) {
        Log ('[3] 检测到 ' + $devs.Count + ' 台设备, 使用 ' + $serial)
    } else {
        Log ('[3] 设备: ' + $serial)
    }

    $sh = "su -c 'grep -v cn1.plt.ms1shanghai.cn /etc/hosts > /data/local/tmp/hosts_rst && cat /data/local/tmp/hosts_rst > /etc/hosts && echo HOSTS_CLEAN_OK'"
    $r = (& $adb -s $serial shell $sh) -join "`n"
    if ($r -match 'HOSTS_CLEAN_OK') {
        $now = (& $adb -s $serial shell "cat /etc/hosts") -join ' | '
        Log ('[3] 模拟器 hosts 已回滚. 当前内容: ' + $now)
        Log '[3] 客户端如仍报无法连接, 请彻底退出并重新打开客户端(重新解析域名).'
    } else {
        Log ('[3] 回滚失败(输出: ' + ($r.Trim()) + ')')
        Log '    — 需要 Root: 在 KernelSU 中为 Shell 授予超级用户权限, 或 MuMu 开发者选项开启 Root.'
    }
}

# ---- 4) 恢复 wotblitz.exe.bak (还原被补丁的游戏客户端) ----
function Restore-Wotblitz {
    $exe = $null
    $st = Join-Path $PSScriptRoot 'launcher_state.json'
    if (Test-Path $st) {
        try {
            $j = Get-Content $st -Raw | ConvertFrom-Json
            if ($j.exe_path) { $exe = $j.exe_path }
        } catch {}
    }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
        $in = Read-Host '[4] 未从 launcher_state.json 读到 wotblitz.exe 路径, 请粘贴完整路径 (回车跳过)'
        if ($in) { $exe = $in.Trim('"').Trim() }
    }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
        Log '[4] 未提供有效路径, 跳过.'
        return
    }
    $bak = $exe + '.bak'
    if (-not (Test-Path -LiteralPath $bak)) {
        Log ('[4] 未找到补丁备份 ' + $bak + ' — 可能从未打过补丁或已恢复过.')
        return
    }
    if (Get-Process -Name 'wotblitz' -ErrorAction SilentlyContinue) {
        Log '[4] wotblitz.exe 正在运行 — 请先退出游戏, 本次跳过.'
        return
    }
    try {
        Copy-Item -Force -LiteralPath $bak -Destination $exe
        Log ('[4] 已用补丁备份恢复: ' + $exe)
    } catch {
        Log ('[4] 恢复失败: ' + $_)
    }
}

# ---- 菜单 ----
while ($true) {
    Write-Host ''
    Write-Host '============ WoTB_CN 一键回滚 (管理员) ============'
    Write-Host ' 1. 回滚电脑 hosts (移除本工具写入的劫持条目)'
    Write-Host ' 2. 删除 WoTB PC 端登录缓存 (DavaProject/packs)'
    Write-Host ' 3. 回滚模拟器 hosts (移除模拟器内 cn1 劫持行)'
    Write-Host ' 4. 恢复 wotblitz.exe.bak (还原被补丁的游戏客户端)'
    Write-Host ' 5. 执行以上全部内容'
    Write-Host ' 0. 退出'
    Write-Host '==================================================='
    $choice = (Read-Host '请输入选项').Trim()
    if ($choice -eq '0' -or $choice -eq 'q' -or $choice -eq '') { break }
    switch ($choice) {
        '1' { Reset-PCHosts }
        '2' { Reset-PCCache }
        '3' { Reset-EmuHosts }
        '4' { Restore-Wotblitz }
        '5' {
            Reset-PCHosts
            Reset-PCCache
            Reset-EmuHosts
            Restore-Wotblitz
            Log '[5] 以上各项已全部执行.'
        }
        default { Log ('无效选项: ' + $choice) }
    }
}
Log '会话结束.'
