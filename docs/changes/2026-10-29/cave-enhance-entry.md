# 洞府强化入口接到现有背包详情

洞府总览的强化入口不新做强化面板，也不改强化公式、炼器精粹或分解规则。

- `dev2` 的地图版 `CavePage` 只声明无参信号 `enhance_entry_requested`，方便和 `proto/dongfu-v1` 三方合并。总览第三张卡在那条分支上发出该信号。
- `PlayScreen` 连接 `enhance_entry_requested` → `open_enhance_entry()`：切到背包，提示「点一件装备进行强化」。身上有还能强化的装备时，按部位顺序（武器优先）用 `BagPage.show_detail` 打开现有 `ItemDetailPopup`。之后的强化仍走 `POST /api/v1/me/items/:id/enhance`。
- 分解仍只从背包（和历练满包）打开 `SalvageDialog`。洞府满包领取若以后要客户端提示，接到 `open_salvage()`，不另做领取界面。
