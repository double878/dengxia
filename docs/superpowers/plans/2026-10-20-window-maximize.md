# Windows 窗口最大化修复计划

> **Execution:** Implement authorized tasks in the current chat, respecting dependency order and the user's stage boundaries. Use subagents only when the user explicitly requests or approves them. Track steps with checkbox (`- [ ]`) syntax.

**Goal:** Windows 最大化/还原及全屏启动后，游戏继续响应，关闭窗口能退出进程。

**Architecture:** 保持 Godot Compatibility 渲染器，仅在 Windows 选择内置 ANGLE 后端。通过真实 Win32 最大化、还原和关闭消息验证源工程及导出包，不以无头通过替代窗口测试。

**Tech Stack:** Godot `4.7.2.stable.official.ed1daf0bf`、对应 Windows 模板、Python 3.13 标准库 Win32 ctypes。

## Global Constraints

- 单切片；保留现有未跟踪文件及 `fix-playtest-polish` 分支，不合入其他功能。
- 全部 Godot 命令使用 `D:\Godot\4.7.2\godot.exe`。
- 不在运行期强制改窗口尺寸，不禁用最大化，不新增运行依赖。
- 外部测试只管理自己启动的进程，超时清理并返回非零退出码。

## Task 1: Windows ANGLE 后端与真实窗口回归

**Files:**
- Modify: `project.godot`
- Create: `tests/b/check_window_resize.py`
- Modify: `TECH_DESIGN.md`
- Create: `docs/window-maximize-delivery.md`

**Interfaces:**
- Consumes: 现有首页、片头、三关场景、Windows 导出预设。
- Produces: `py -3.13 tests/b/check_window_resize.py [--exe builds/dengxia.exe] [--fullscreen] [--scene res://scenes/act2/opening.tscn] [--intro]`。
- 程序每次记录窗口响应、尺寸、正常关闭和退出码；任何失败返回 1。

- [x] **Step 1: 复现失败并对照单一变量。**
  原版首页收到 `WM_SYSCOMMAND/SC_MAXIMIZE` 后 `WM_NULL` 超时，`WM_CLOSE` 后 4 秒仍不退出；同代码增加 `--rendering-driver opengl3_angle` 后相同操作均响应、正常退出 0。
- [x] **Step 2: 固化原生窗口回归。**
  `EnumWindows` 只选择测试进程的可见窗口；通过 `PostMessageW` 发两轮最大化/还原，用 `SendMessageTimeoutW(..., SMTO_ABORTIFHUNG, 1500, ...)` 验证响应；最后发 `WM_CLOSE` 并等待最多 4 秒。`finally` 只清理本测试仍存活的进程。加入实际片头 Enter 输入、完整全屏启动和独立场景参数。
- [x] **Step 3: 修改唯一运行配置。**

  ```ini
  [rendering]
  gl_compatibility/driver.windows="opengl3_angle"
  ```

- [x] **Step 4: 定向验证与三项门禁。**
  先 `py -3.13 -m py_compile tests/b/check_window_resize.py`；执行源工程首页、片头、各关及全屏窗口检查。导入、`--quit-after 60`、Windows release 导出都应退出 0；源工程媒体图形回归应无失败。正式导出前检查没有运行中的目标 exe。
- [x] **Step 5: 导出包实际验收与收尾。**
  对 `builds/dengxia.exe` 执行首页、片头、全屏原生窗口检查，确认渲染日志确实使用 ANGLE；查看最大化画面，检查错误日志、Git diff 和用户文件保留情况，清理临时探针。仅暂存本切片文件，提交后推送修复分支。
