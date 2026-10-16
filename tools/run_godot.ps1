param(
    [Parameter(Mandatory = $true)][string]$LogName,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$GodotArgs
)

$ErrorActionPreference = 'Stop'
$stageRoot = Split-Path -Parent $PSScriptRoot
# PCK 的文件目录缓存在运行进程中；覆盖原包会让旧进程按旧偏移读取新内容。
for ($stageArgIndex = 0; $stageArgIndex -lt $GodotArgs.Count; $stageArgIndex++) {
    if ($GodotArgs[$stageArgIndex] -notin @('--export-release', '--export-debug', '--export-pack')) {
        continue
    }
    if ($stageArgIndex + 2 -ge $GodotArgs.Count) {
        continue
    }
    $stageExportPath = $GodotArgs[$stageArgIndex + 2].Trim('"')
    if (-not [System.IO.Path]::IsPathRooted($stageExportPath)) {
        $stageExportPath = Join-Path $stageRoot $stageExportPath
    }
    $stageExportExe = [System.IO.Path]::ChangeExtension(
        [System.IO.Path]::GetFullPath($stageExportPath), '.exe'
    )
    $stageExportProcesses = @(Get-Process `
        -Name ([System.IO.Path]::GetFileNameWithoutExtension($stageExportExe)) `
        -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.Equals($stageExportExe, [System.StringComparison]::OrdinalIgnoreCase)
        })
    if ($stageExportProcesses.Count -gt 0) {
        $stageRunningIds = ($stageExportProcesses | ForEach-Object { $_.Id }) -join ', '
        throw "目标游戏仍在运行（PID: $stageRunningIds）：$stageExportExe。请先关闭该游戏再导出，或使用不同的导出文件名。"
    }
}
$stageLogDir = Join-Path $stageRoot 'builds\stage-realism\logs'
New-Item -ItemType Directory -Path $stageLogDir -Force | Out-Null
# 日志、截图与临时入口不作为 Godot 项目资源导入或打包。
$stageBuildIgnore = Join-Path $stageRoot 'builds\.gdignore'
if (-not (Test-Path -LiteralPath $stageBuildIgnore)) {
    New-Item -ItemType File -Path $stageBuildIgnore | Out-Null
}
$stageOut = Join-Path $stageLogDir ($LogName + '.out.log')
$stageErr = Join-Path $stageLogDir ($LogName + '.err.log')
# PowerShell 对 GUI 子进程的直接调用可能提早返回；显式等待，记录真实退出码。
$stageProcess = Start-Process -FilePath 'D:\Godot\4.7.2\godot.exe' `
    -ArgumentList $GodotArgs -WorkingDirectory $stageRoot -WindowStyle Hidden `
    -PassThru -Wait -RedirectStandardOutput $stageOut -RedirectStandardError $stageErr
Get-Content -LiteralPath $stageErr
Get-Content -LiteralPath $stageOut -Tail 15
Write-Output ('GODOT_EXIT=' + $stageProcess.ExitCode)
exit $stageProcess.ExitCode
