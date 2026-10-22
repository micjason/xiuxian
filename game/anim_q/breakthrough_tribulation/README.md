<!-- 客户端入库：横幅字体不另存 TTF，场景改指 res://assets/fonts/ZCOOLQingKeHuangYou-Regular.subset.woff2（与 anim_q/breakthrough 相同，SIL OFL 1.1）。 -->

# 天雷渡劫 · 突破成功（10 秒）

新版境界突破特效：聚气压暗 → 天雷连劈渡劫 → 短静 → 金光爆发「突破成功」。
旧版短特效仍保留在 `anim_out_q/breakthrough/`（约 4.4 秒），本目录是独立的新序列，互不影响。

预览：`../preview/tribulation.mp4` / `tribulation.gif`（叠在突破弹窗设计稿上，opengl3 录制）。
截图（jpg < 500KB，另有 png 原图）：
- `screenshot_thunder.jpg`：渡劫中段，天雷劈落
- `screenshot_success.jpg`：金光爆发 + 「突破成功」横幅
- 另附 `screenshot_gather.jpg`（聚气压暗）、`screenshot_final_strike.jpg`（末雷）


## 成功段加强（10/22 反馈后）
针对「最后金光不够」：成功阶段改为普通混合（亮底 UI 上 additive 会发灰）、加粗金光柱双层、金爆光晕、日芒更久、4 圈扩散环、主角身后金光、横幅弹跳+背光；粒子更多更快升；峰值约 0.3–0.5 秒后回落，不长时间挡板。
截图：`screenshot_success.jpg`（峰值）、`screenshot_success_mid.jpg`（回落后仍见横幅）。

## 时间轴（合计 10 秒）
| 阶段 | 时间 | 表现 |
|---|---|---|
| 聚气 | 0.0 – 1.8s | 全屏压暗、乌云聚拢、法阵亮起、灵气向内收、主角微抬 |
| 渡劫 | 1.8 – 7.55s | 10 道落雷（越往后越重）+ 末雷；闪白、震屏、电光火花 |
| 寂静 | 7.55 – 8.05s | 短停顿，云散压暗回落 |
| 成功 | 8.05 – 10.0s | 金光柱、日芒、扩散环、金色粒子升腾、「突破成功」横幅弹出 |

信号：`phase_changed(phase)`（`gather` / `tribulation` / `silence` / `success` / `done`）、`strike(index)`、`finished`。
常量：`DURATION = 10.0`；`duration()` 同值。

## 开发怎么接
1. 把本目录整份拷到游戏工程的 `anim_q/breakthrough_tribulation/`（含 `fx/`、`art/`、`font/`、`.tscn`、`.gd`）。
2. 在突破弹窗（或修炼页全屏层）实例化 `tribulation_fx.tscn`，锚点放在主角脚下（设计稿约 `(540, 892)`，与旧版 `breakthrough_fx` 同位置）。
3. 把主角（建议复用 `hero_meditate.tscn`，或弹窗里的立绘）挂到 `World/HeroSlot` 下；需要莲台可自行加子节点。
4. 玩家点「突破」且服务端确认成功后调用：
```gdscript
fx.banner_text = "突破成功"   # 可改成「突破 · 筑基一层」等
fx.play()
await fx.finished            # 或连 finished 信号后再关弹窗 / 刷属性
```
5. 导出属性：
   - `use_dim`（默认 true）：全屏压暗；若页面自己有遮罩可关
   - `shake_mul`（默认 1.0）：震屏强度，低端机可调到 0.5
   - `banner_text`：成功横幅文字
   - `autoplay`：预览用，游戏里保持 false

不要显示「暴击」。本特效是 UI 叠加层，不会挡战斗血条/名字。

## 要拷的文件
整个 `anim_out_q/breakthrough_tribulation/`：
- `tribulation_fx.tscn` / `tribulation_fx.gd`
- `fx/`（雷电、云、光晕、粒子、旧突破复用贴图、sunburst 等）
- `art/ribbon_title_104.png`
- `font/ZCOOLQingKeHuangYou-Regular.ttf`（与旧突破同款站酷庆科黄油体）

不改 `xiuxian-ui` 仓库；由开发二号接到突破流程。旧 `breakthrough/breakthrough_fx.tscn` 可继续给短反馈用，或逐步换成本序列。

## 性能（低端安卓）
- 节点约 42 个；落雷 7 个 Sprite 池化复用，不运行时 new
- 粒子：聚气 28 + 火花 22 + 余烬 18 + 金爆 40 + 升金 20，均 CPUParticles2D，用完即停
- 无 Spine；震屏只改 `World.position`
- 压暗是一张 ColorRect；闪白是 CanvasLayer 上的 ColorRect
- 真机若掉帧：`shake_mul = 0.5`，或把 `fx/fx_bolt_*.png` 再缩小一档

## 校验
- 无头加载：`tribulation_fx.tscn` 42 节点，`play()` / `duration()==10` / 7 道雷池，无脚本报错（`_preview_project/tools/trib_load_check.gd`）
- 录屏：Compatibility / opengl3，`--write-movie`，11 秒含片头余量

## 重建（可选）
```bash
# 在 _preview_project 里
Godot --headless --path . --script res://tools/build_tribulation.gd
bash tools/render.sh tribulation 11.0
```
