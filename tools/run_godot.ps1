param(
    [Parameter(Mandatory = $true)][string]$LogName,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$GodotArgs
)

$ErrorActionPreference = 'Stop'
$stageRoot = Split-Path -Parent $PSScriptRoot
$stageLogDir = Join-Path $stageRoot 'builds\stage-realism\logs'
New-Item -ItemType Directory -Path $stageLogDir -Force | Out-Null
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
