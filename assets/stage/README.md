# 舞台材质

`cotton_weave.png` 与 `wood_grain.png` 是本项目程序生成的原创纹理，无第三方图像。重建：`python tools/generate_stage_textures.py`（仅重建工具需要 Pillow，游戏无新增依赖）。固定种子 20261008。

棉纹为中灰细经纬、纤维不匀与周期厚薄变化；材质中小幅调制漫透射，不作为布料透光率测量。木纹为暖灰棕长纹。灯色、透射强度、半影宽度均为设计值，调研依据与地域限制见 `docs/stage-realism-plan.md`。
