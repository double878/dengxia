# 第二关手动出场实施计划

**Goal:** 数字键让法海首次从树右后、许仙首次从门内露出一点；空格接手后由玩家拖出，退场再上场恢复原处。

**Architecture:** 开场宿主维护每人的出场完成状态。独立 `scripts/act2/act2_entrance.gd` 根据现有布景生成固定遮挡遮罩；`PlaceholderPuppet.entrance_mask` 默认为空，仅第二关首次出场时使用，实体与投影共享舞台坐标遮罩。遮挡不写操控状态，也不参与第一关判定。

**Tech Stack:** Godot 4.7.2 Standard、GDScript、CanvasItem shader；不增加依赖。

## 约束和确认

- 用户已确认 1B / 2A / 3A / 4B / 5A 并回复“按这个做”。法海朝左、许仙朝右；数字键不自动接手或移动。
- 保留 200 身高、661 px 地面、操作手、暂停、空格循环和右键退场。
- 首次出场未完成时误退场也保留进度；完全走出后不再次遮挡。
- 不修改场景、工程配置、布景原图、对白或整关录放；不使用子智能体。
- 在 `feat-act2-entrances` 上实现，保留尚在 PR #11 的人物尺寸提交。

## 实施与验收

- [x] 在 `tests/c/run_act2_entrances.gd` 扩展既有输入测试工具：验证入口位置、手动移动、暂停、部分走出后恢复、完全走出后返回不遮挡。先执行解析和定向测试，确认旧实现因入口与遮挡缺失失败。
- [x] 新建 `act2_entrance.gd`，用门洞右门框和柳树实心外轮廓生成像素遮罩。宿主首次放置影人、每帧检查实体与投影均已脱离入口，再永久解除该人的遮罩。
- [x] 两个现有影人 shader 引入可选遮罩，默认关闭；屏幕外竹签与操作手保留。Windows 实际渲染比较遮挡/无遮挡像素，并保存出场前、过程中、走出后的截图。
- [x] 更新既有操演测试的朝向和拖动路径，使它继续验证正确角色、松手、切换和重复上下场；运行相关第一关视觉回归。
- [x] 解析、gdformat / gdlint、导入、60 帧启动、Windows Release 导出；直接审查差异，记录实际证据，清理临时产物。

交付方式：只暂存本功能文件，提交并推送分支，创建 PR；本轮不合并主干。实际验证见 `docs/act2-opening-delivery.md` 对应日期的手动出场记录。

## 验证命令

统一用 `tools/run_godot.ps1` 调用 `D:\Godot\4.7.2\godot.exe`：

```powershell
& .\tools\run_godot.ps1 -LogName entrance-parse -GodotArgs @('--headless','--path','.','--check-only','--script','res://tests/c/run_act2_entrances.gd')
& .\tools\run_godot.ps1 -LogName entrance-headless -GodotArgs @('--headless','--path','.','--script','res://tests/c/run_act2_entrances.gd')
& .\tools\run_godot.ps1 -LogName entrance-graphics -GodotArgs @('--path','.','--script','res://tests/c/run_act2_entrances.gd')
& .\tools\run_godot.ps1 -LogName entrance-opening -GodotArgs @('--path','.','--script','res://tests/c/run_act2_opening.gd')
& .\tools\run_godot.ps1 -LogName entrance-level1 -GodotArgs @('--path','.','--script','res://tests/b/run_stage_walk.gd')
& .\tools\run_godot.ps1 -LogName entrance-import -GodotArgs @('--headless','--path','.','--import')
& .\tools\run_godot.ps1 -LogName entrance-startup -GodotArgs @('--headless','--path','.','--quit-after','60')
& .\tools\run_godot.ps1 -LogName entrance-export -GodotArgs @('--headless','--path','.','--export-release','"Windows Desktop"','builds/dengxia.exe')
```
