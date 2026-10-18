# 仙翁、白鹿、白鹤影人素材

> **2026-10-14 新形象替换**：本节取代下方旧版低清重绘说明与验证结果。最新形象直接取自用户提供的三张图片：图 1 为仙翁，图 2 为鹤童，图 3 为鹿童。旧截图和旧验证 JSON 留作历史记录，不能作为当前版本证据。

新形象保留原图五官、服饰和纹样：仙翁为高额白须、红披肩、金色寿纹袍；鹤童为羽冠红缨、青色云肩、白衣羽纹；鹿童为莲花冠、青蓝鹿纹衣和回纹靴。原图白底已去除，白衣、白须保留暖色皮革细节。没有提供独立反面，翻面仍使用整体镜像。

用户复核后，鹿童、鹤童的游戏内头部等比缩小为提取版的 65%，与同身高白素贞对比脸部大小；仙翁沿用原尺寸。该比例记录在生成工具的 `HEAD_SCALE_BY_CHARACTER` 和清单的 `head_scale`，重建不会丢失。`lineup.png` 与 `*-pose.png` 保留原图提取比例，游戏中的最终头身比例以 `godot-rest.png`、`godot-arms.png` 和第三幕截图为准。

当前三套图集仍为 2048×2048 RGBA、512×512 分件格，每套 13 件。头、上臂、前臂、手支持现有姿态；新增 `lower_body` 保留连续袍摆/裤腿轮廓，随整体走位、身体起伏和站蹲缩放，避免照片拆腿后产生拼贴裂缝。左右腿分件仍留在图集中，但这三套外观的实际显示使用连续下半身，不显示分腿迈步或膝关节外张；原有角色继续使用原来的腿部绘制。仙翁原图没有拐杖，当前素材不额外添加。

运行时注册编号沿用 4/5/6（仙翁/鹿童/鹤童），通过 `skin_override` 显式使用。第三幕当前剧情仍只有白素贞与鹿童，鹿童的实体、投影和幕前回放均读取替换后的编号 5；仙翁与鹤童的外观已可加载，本轮没有增加新的出场剧情。

三个原图保存在 `assets/puppets/immortals/source/*-reference.png`，SHA-256、原始尺寸及分件坐标记入 `immortals-assets.json`。坐标现在指各自原图，包含白边。SVG 内嵌当前 PNG，分件轮廓与枢轴的可编辑源为 `tools/prepare_immortal_reference_assets.py`，不再声称是重新绘制的矢量线条。

重建命令：

```powershell
py -3.13 -m py_compile tools/prepare_immortal_reference_assets.py tools/build_immortal_assets.py
py -3.13 tools/build_immortal_assets.py
```

已有三个新参考图时，旧制作入口自动调用新分件流程；仅显式传入旧图 `--reference` 才会切回旧矢量重绘。制作依赖复用 Pillow/NumPy，没有新增游戏运行依赖。

当前预览：`lineup.png` 为透明素材合图；`preview.html` 为独立分件身段查看工具，其腿部控件使用保留的分腿稿，不代表游戏连续下半身的蹲站效果。`godot-rest.png`、`godot-arms.png`、`godot-mirrored.png` 为 Windows 实际显示端截图；`act3-stage.png`、`act3-replay.png` 为第三幕实体和真实记录回放的截图。

本轮验证命令与日志（统一 Godot：`D:\Godot\4.7.2\godot.exe`，版本 `4.7.2.stable.official.ed1daf0bf`）：

- `--headless --path . --check-only --script scripts/a_test/placeholder_puppet.gd`：退出码 0。
- `--headless --path . --import`：退出码 0。
- `--headless --path . --script tests/a/run_upper_body.gd`：100 条断言通过。
- `--headless --path . --script tests/b/run_stage_visuals.gd`：379 条断言通过。
- `--headless --path . --script tests/c/run_act3_entrance.gd`：27 项检查、0 失败。
- `--headless --path . --script tests/a/run_tests.gd`：汇总 1284 条断言通过、0 失败，随后正式对白补测 22 条断言通过；含非法输入测试预期报错与退出资源释放提示。
- `--headless --path . --script tests/c/run_tests_c.gd`：463 条断言通过、0 失败；非法记录测试的预期拒绝日志保留。
- Windows 临时图形入口：三位外观的站立、双臂、镜像与前倾，实际第三幕鹿童及同一次演出的幕前回放；退出码 0、错误日志为空。入口在验证后删除。
- `--headless --path . --quit-after 60`：退出码 0，但仍有 2 个 ObjectDB 实例和 1 个资源未释放提示；不宣称清洁退出。
- `--headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"`：退出码 0，生成 EXE/PCK。

当前日志位于 `builds/immortal-reference/`。本轮没有进行音频听验或完整 101 秒人工试玩；图形探针使用实际状态、采集和回放入口验证新贴图，不代替完整剧情体验验收。

头部缩小后的再次验证日志为 `head-import.*.log`、`head-probe-parse.*.log`、`head-probe.*.log`、`head-smoke.*.log`、`head-export.*.log`，五项退出码均为 0，图形入口错误日志为空；启动释放提示仍存在。最终同身高截图的顺序为白素贞、鹿童、鹤童、仙翁。

---

以下为旧版制作记录。

按用户确认制作：三位均为人形；保留参考轮廓、头饰、脸色、袍服主色，模糊与遮挡区域补绘；本轮交付素材和独立可动预览。

## 看形象

打开本目录 preview.html。离线运行，无外部依赖，可选择人物、抬臂、屈肘、点头、前倾、蹲姿、整体翻面、拆件和演示/暂停身段。单人查看会保留长袖与拐杖的完整取景。

lineup.png 是三人合图，顺序为白鹿、白鹤、仙翁。三个 *-pose.svg/png 是完整参考姿态。preview-desktop.png、动作截图、拆件截图及 preview-mobile.png 是实际 Chrome/Windows 验收截图。

## 文件与分件

素材目录：assets/puppets/immortals/。

- xianweng.svg/png：仙翁，高额、白须、黄袍、拄杖。
- bailu.svg/png：白鹿/鹿童，鹿角冠、赭红脸、深绿袍。
- baihe.svg/png：白鹤/鹤童，鹤形冠、白脸黑线、深青袍。
- immortals-assets.json：来源、尺寸、分件矩形、枢轴、轴长、父子关系及补绘说明。
- source/reference.png：用户提供的 335×301 参考图；该目录用 .gdignore 排除 Godot 导入。

每套图集 2048×2048，分件格 512×512。每个角色 12 个身体分件：头、躯干、左右上臂/前臂/手、左右大腿/小腿。第 13 件为仙翁拐杖，或鹿童/鹤童的冠后飘带。裙片互相覆盖，形成连贯袍服轮廓。镂空处为真实透明，PNG 不包含幕布或操作签。

SVG 由 Python 描述的轮廓及花纹生成，PNG 由同一 SVG 经项目固定版本 Godot 光栅化。可直接编辑 SVG；重新运行制作脚本会覆盖手动修改的生成文件，因此需要持久保留的修改应同步到制作脚本。

角色清单沿用现有图集字段，但独立于 puppet_assets.json；暂用外观编号 4/5/6。清单中的 reference_axis 和 reference_bounds 指 **560×1010 重绘稿坐标**，不是原图像素坐标。运行时整合仍需注册图集、清单、附件以及角色/头部映射并验证实际游戏操控。本轮没有修改该映射或接入第三幕剧情。

## 参考与补绘边界

参考图左、中、右分别按用户确认制作鹿童、鹤童、仙翁；原始朝向为画面右。图像低清，无法可靠辨认原纹样、精确五官、铆钉及不可见肢体。因此花纹、连接余量、裙片、鞋靴、冠饰细部与杖头均有补绘；三人的完整衣袍不是从截图直接抠取，也不声称是原物的精确摹刻。

未提供独立反面，采用整体镜像。PNG 的透明孔洞不等于实测皮革透光率，接入游戏时仍使用舞台材质实现透射。预览是素材验收工具，不能代替 Godot 实际操控与回放验收。

## 重建与实际验证

~~~powershell
py -3.13 -m py_compile tools/build_immortal_assets.py
py -3.13 tools/build_immortal_assets.py
~~~

首次重建可传 --reference <用户参考图路径>。Python 依赖复用现有 Pillow/NumPy；Godot 固定为 D:\Godot\4.7.2\godot.exe、4.7.2.stable.official.ed1daf0bf，未新增运行时依赖。

本轮执行结果：

- 资产检查通过：三套 PNG 均为 2048×2048 RGBA，每套 13 件；背景透明、分件有内容、格边无裁切、连接枢轴检查通过。详见 asset-checks.json。
- 实际 Chrome/Windows 检查通过：三人展示、独立人物选择、手臂/肘/头/腰控制、整体镜像、复位、持杖层级、拆件、演示与暂停、蹲姿、深色幕布；390 px 页面无横向溢出，未出现 JavaScript 异常。详见 browser-checks.json。
- 人工检查合图、原姿态及动作截图；修正了镂空裁切产生的孤立色点与长杖取景裁切。
- Godot 导入通过：godot.exe --headless --path . --import，退出码 0。
- Godot 启动执行：godot.exe --headless --path . --quit-after 60，退出码 0，仍有 2 ObjectDB instances were leaked 和 1 resources still in use at exit。此前 builds/stage-realism/logs/act1-clean-exit-smoke.err.log 也有相同提示；这不属于本轮素材的清洁启动证明。
- Windows 导出通过：godot.exe --headless --path . --export-release "Windows Desktop" "builds/dengxia.exe"，退出码 0。使用既有 tools/run_godot.ps1 留存日志；该封装的导出预设需要保留双引号，实际参数为 --export-release '"Windows Desktop"'。第一次导出因封装丢失引号被识别为 Windows 而失败，修正调用参数后成功，没有修改预设或封装。

门禁日志：builds/stage-realism/logs/immortals-import.*.log、immortals-startup.*.log、immortals-export-final.*.log。

本轮新增独立素材、制作工具、预览及说明；现有工作区修改保留。未运行无关整套玩法测试，也未验证第三幕游戏内操控、幕前回放、真实皮革透光或独立反面。
