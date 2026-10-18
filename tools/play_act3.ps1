# 交互式排练入口：第三幕完整演出，谢别后玩家 W 跳起、右键退场，再收场与回放。
$ErrorActionPreference = 'Stop'
$act3Root = Split-Path -Parent $PSScriptRoot
$act3Executable = Join-Path $act3Root 'builds\dengxia.exe'
if (-not (Test-Path -LiteralPath $act3Executable -PathType Leaf)) {
    throw '缺少 builds/dengxia.exe，请先按 TECH_DESIGN.md 执行 Windows 导出。'
}
Start-Process -FilePath $act3Executable -WorkingDirectory $act3Root `
    -ArgumentList @('--', '--act3-rehearsal') -WindowStyle Normal
