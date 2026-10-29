# 突破成功改播天雷渡劫

## 决定

服务端确认突破成功后，播放 `game/anim_q/breakthrough_tribulation/tribulation_fx.tscn`（`TribulationFx.DURATION` = 10 秒），横幅文案「突破成功」。播完 `finished` 再刷突破页、弹出结算。

短特效 `game/anim_q/breakthrough/breakthrough_fx.tscn` 仍负责弹窗舞台的 idle，以及点「突破」后、请求返回前的 charge。正式成功路径不再播它的 success，也不显示「暴击」。

请求返回前不再用 `CHARGE_SECONDS`（2 秒）把充能播完才接成功演出。天雷自己从聚气开始。

## 接入

- 素材在 `game/anim_q/breakthrough_tribulation/`。横幅字体改指已有的 `assets/fonts/ZCOOLQingKeHuangYou-Regular.subset.woff2`，不另存一份 TTF。
- `QFx.TRIBULATION` / `QFx.TRIBULATION_SECONDS`。
- 突破页把 `hero_meditate` 挂到 `World/HeroSlot`（莲台、隐藏坐垫，和舞台同一套），`autoplay = false`，`use_dim = true`，`shake_mul = 1`。
- 锚点跟舞台短特效同一个点（设计稿约 (540, 892)）。压暗按这个锚点铺满视口。

## 还没做

- 没有打 APK，没有改服务器，没有替换结算弹窗里的短特效 idle 装饰。
- 预览 mp4 不进仓库。
