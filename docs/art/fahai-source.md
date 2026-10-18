# 法海素材制作说明

- 来源：用户在本次会话提供的 `codex-clipboard-92858ccc-7217-4cfd-85eb-d090a4b119e9.jpg`，1280×1653。
- 原稿：`assets/puppets/source/fahai-reference.jpg`。保留原图来源证据；本记录不额外声明第三方授权状态。
- 制作：`tools/build_fahai_assets.py` 按手工轮廓提取 12 个身体分件、帽后饰带和独立锡杖，共 14 件，保留源像素的帽、卷须、田相袈裟、花袖和法器装饰。
- 输出：`assets/puppets/fahai.png` 为 2048×2048 atlas，每格 512×512；`fahai-cutout.png` 为整身透明素材预览，不是最终骨架摆姿。
- 白底和白色刻线用估算 alpha 处理，保留彩色皮片。JPEG 没有真实透明度，颜色与透光不是材质测量值。
- 正反面共用同一份分件并水平翻转，没有独立背面参考。关节装配和铜钉由现有渲染完成，锡杖跟随右腕，饰带跟随躯干。
- 生成环境：Python 3.13、Pillow、NumPy，执行 `py -3.13 tools/build_fahai_assets.py`。这些库仅用于素材制作。
