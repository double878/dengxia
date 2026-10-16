# 第二幕剧情顺序修订

2026-10-13。按用户最新要求与「先用临时对唱字幕演练」选择实现。只修改厅堂剧情与既有补救适配，不制作新唱腔或对白音频。

## 当前流程

白素贞「小青，你就去吧」→ 小青「好吧」→ 玩家让小青从左台边退场 → 许仙与白素贞饮前对唱 → 取杯、递杯、饮酒 → 玩家让白素贞实际弯腰 → 白素贞以普通对白说身体不适 → 许仙以普通对白说去取药 → 玩家让许仙从右台边离场 → 原压灯换蛇、显形、返回惊死流程。

对唱目前是明确标注「临时对唱」的四句字幕，两人各两句、每句 4.5 秒；词句和时长只是排练占位，正式唱腔制作时替换。无声字幕不能算音频或听感验收。对唱结束之前不能取杯、递杯、饮酒；演员缺场和菜单暂停时冻结段落。

饮后先接手白素贞，按住 Alt 向她面朝的方向拖躯干，实际腰角达到 20°便触发不适对白，不额外要求保持。如果饮前已经弯腰到位，先按 R 扶正或扶正到 10°以下，再做饮后动作。另一演员、提前摆好的姿态、等待超时和师父补救均不能替代。弯腰复用原 8 秒准备和 8 秒补救，实际完成后收起示范手、停止慢锣鼓，再继续普通对白。

## 本轮验证

使用同一 Godot `4.7.2.stable.official.ed1daf0bf` 与 `4.7.2.stable` 模板。

- 六个修改脚本逐一 `--headless --path . --check-only --script res://<文件>` 通过；`gdformat --check`、`gdlint` 和 `git diff --check` 通过。
- `tests/c/run_act2_actions.gd`：85 项，0 失败。先观察旧实现的新增回归失败，再实现；覆盖应答、饮前对唱、提前取杯拒绝、演员缺场、饮后旧姿态、另一演员、超时与暂停。
- `tests/c/run_act2_remedy.gd`：Windows 图形环境 26 项，0 失败；包含对唱不判漏做、弯腰补救、暂停和补救超时不代演。
- `tests/b/run_act2_actions_graphics.gd`：Windows 实际宿主输入走完整流程并保存截图。目视核对小青应答、对唱、饮后尚未弯腰、弯腰师父示范与不适对白；补救真实混音峰值 0.105447。
- 厅堂衔接 39 项、第一幕正式编排 22 项通过。
- 独立工作区资源导入、无头启动和 Windows 导出退出 0；启动保留已知的 2 个 ObjectDB / 1 个 resource 退出释放提示，未称为无警告。

日志在 `builds/stage-realism/logs/plot-*.out.log` / `.err.log`；截图在 `builds/act2-actions/`，新增 `qing-reply.png`、`duet-xu.png`、`duet-bai.png`、`before-bend.png`、`remedy-bend.png`、`bai-unwell.png`。构建和截图不入版本库。

## 原工程接入

已接回 `D:\Cursor_program\灯下`，保留原分支和用户已有修改。接入前逐文件核对 `ff39307` 基线，PRD/README 只替换本轮相关段落、TECH_DESIGN 只插入修订说明；56 个其他已有文件经 SHA256 核对未变。原工程再次完成六脚本解析、动作 85 项、Windows 补救 26 项、Windows 全流程与混音；`--headless --path . --import`、`--headless --path . --quit-after 60`、`--headless --path . --export-release "Windows Desktop" builds/dengxia.exe` 均退出 0，正式 EXE 在 Windows 图形环境启动退出 0。原工程无头启动同样保留已知的 2 个 ObjectDB / 1 个 resource 释放提示。临时整合脚本已清理，正式回归测试保留。

原工程试玩入口仍为 `builds/第二幕试玩.cmd`。第二关正式唱腔、整关评分、录放及第三幕未包含在本轮交付中。未使用子智能体，按用户要求直接审查差异并执行验证；没有独立代码评审。
