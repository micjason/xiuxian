# Android 应用内更新 Demo

## 已实现

- `0.1.0`：用于首次安装，启动后访问公开更新地址。
- `0.1.1`：公开更新版本，页面增加“0.1.1 更新版已启动”标记。
- `0.1.2`：第一个可玩闭环。打开后自动检查并覆盖安装；进入后可见修为、境界、突破和离线补发。
- `0.1.3`：关闭“作为桌面启动器”，应用会出现在普通应用列表；安装前会再次校验，避免误装上次留下的旧包。
- `0.1.4`：主界面润色、突破与离线反馈、修炼简记，并加快前三阶手感。
- `0.1.5`：覆盖安装按更高 `versionCode` 判断，并把 FileProvider 读权限授给系统安装器。旧客户端仍可能只提示「打开」，这次用 USB 覆盖。
- `0.1.6`：打开历练第二条循环（挂机战斗、行囊、装备、功法、设置）。`versionCode` 7，供已装 `0.1.5`（code 6）的手机覆盖安装。
- `0.1.7`：安装改为系统 `PackageInstaller` 会话。`0.1.5`/`0.1.6` 的 FileProvider 路径在 ColorOS 上会让安装器读到已装包，从而提示「已安装更高版本 0.1.5」。`versionCode` 8。已装 `0.1.5` 的手机需要 USB 装一次，之后热更走新安装器。
- `0.1.8`：同一安装器上的覆盖验证包。`versionCode` 9，供已装 `0.1.7`（code 8）的手机热更。
- `0.1.9`：供已装 `0.1.8` 的手机脱离电脑自测热更。`versionCode` 10。
- `0.1.10`：玩法调表。前三阶放慢、修为接到金丹、掉落节流、关卡墙抬高、行囊对比战力。`versionCode` 11。
- `0.1.11`：五页显示。公共顶栏（境界 / 修为 / 战力），行囊点开对比，历练地点列表，功法已学置顶。`versionCode` 12。
- `0.1.12`：字号与占位。顶栏两行、主按钮 96、地点列表收成短行、简记让出主区。`versionCode` 13。
- `0.1.13`：行囊改版。角色居中五槽环绕、已穿不进袋、四列分类网格、详情弹窗；装备加攻防速与品质词条。`versionCode` 14。
- `0.1.14`：五小时循环。同名合并、关卡短板墙、一地三层、同阶套装、功法小成、丹药限时、材料温养、历练见闻。`versionCode` 15。
- `0.1.15`：功法运转。路数生效、运转栏、功法页可点、天阶锁到金丹初、古碑台功法墙。`versionCode` 16。

## 0.1.15 发布记录（2026-09-11）

- 应用版本 `0.1.15`，`versionCode` 16。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/release-0.1.15`（`v0.1.15` 已给早期频道用过，不能复用）。
- 公开仓频道标签：`v0.1.22`。
- 安装包 asset `556636274`，`apk_sha256` 前缀 `135ba1eb`。
- 用途：已装 `0.1.14` 的手机用游戏内检查更新覆盖。存档 schema 4，能加载 0.1.14 的 schema 3。

## 0.1.14 发布记录（2026-09-11）

- 应用版本 `0.1.14`，`versionCode` 15。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/release-0.1.14`（`v0.1.14` 已给早期频道用过，不能复用）。
- 公开仓频道标签：`v0.1.21`。
- 安装包 asset `556525118`，`apk_sha256` 前缀 `1eba8f03`。
- 用途：已装 `0.1.13` 的手机用游戏内检查更新覆盖。存档 schema 3，能加载 0.1.13 的 schema 2。

## 0.1.13 发布记录（2026-09-11）

- 应用版本 `0.1.13`，`versionCode` 14。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/release-0.1.13`（`v0.1.13` 已给早期频道用过，不能复用）。
- 公开仓频道标签：`v0.1.20`。
- 安装包 asset `556335040`，`apk_sha256` 前缀 `7b1d446d`。
- 用途：已装 `0.1.12` 的手机用游戏内检查更新覆盖。

## 0.1.12 发布记录（2026-09-10）

- 应用版本 `0.1.12`，`versionCode` 13。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/release-0.1.12`（`v0.1.12` 已给早期频道用过，不能复用）。
- 公开仓频道标签：`v0.1.19`。
- 安装包 asset `554793356`，`apk_sha256` 前缀 `15e8dff5`。
- 用途：已装 `0.1.11` 的手机用游戏内检查更新覆盖。

## 0.1.11 发布记录（2026-09-10）

- 应用版本 `0.1.11`，`versionCode` 12。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/release-0.1.11`（`v0.1.11` 已给早期频道用过，不能复用）。
- 公开仓频道标签：`v0.1.18`。
- 安装包 asset `554762031`，`apk_sha256` 前缀 `b1551c6c`。
- 用途：已装 `0.1.10` 的手机用游戏内检查更新覆盖。

## 0.1.10 发布记录（2026-09-10）

- 应用版本 `0.1.10`，`versionCode` 11。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/release-0.1.10`（公开仓里的 git 标签 `v0.1.10` 已给 0.1.4 频道用过，不能复用）。
- 公开仓频道标签：`v0.1.17`。
- 安装包 asset `554650835`，`apk_sha256` 前缀 `cc296bc8`。
- 用途：已装 `0.1.9` 的手机用游戏内检查更新覆盖。手机未连电脑时不要等 USB。

## 0.1.9 发布记录（2026-09-10）

- 应用版本 `0.1.9`，`versionCode` 10。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/v0.1.9`
- 公开仓频道标签：`v0.1.16`。
- 安装包 asset `554575809`，`apk_sha256` 前缀 `54be277c`。
- 用途：手机已装 `0.1.8` 后，断开电脑，用游戏内检查更新自测覆盖。

## 0.1.8 发布记录（2026-09-10）

- 应用版本 `0.1.8`，`versionCode` 9。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/v0.1.8`
- 公开仓频道标签：`v0.1.15`。
- 安装包 asset `554550059`，`apk_sha256` 前缀 `34a3310f`。
- 用途：已 USB 装上 `0.1.7` 的手机，用游戏内检查更新覆盖到 `0.1.8`。

## 0.1.7 发布记录（2026-09-10）

- 应用版本 `0.1.7`，`versionCode` 8。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/v0.1.7`
- 玩法与 `0.1.6` 相同；只修覆盖安装。
- 根因复查：jsDelivr `@latest` 与 GitHub asset `554465417` 的 `0.1.6` 包确为 `versionCode` 7、哈希 `6c5e7969…`。下载校验通过后系统仍提示「已安装更高版本 0.1.5」，说明安装器没有解析刚下载的 APK，而是回退显示已装包。
- 修复：把 APK 写入 `PackageInstaller` 会话；安装前再读文件内 `versionCode`；FileProvider 仅作底线。
- 公开仓频道标签：`v0.1.14`（不要复用 `v0.1.13`）。
- 安装包 asset `554540367`，`apk_sha256` 前缀 `a4396888`。
- 覆盖条件：手机已装 `versionCode` < 8。`0.1.5` 客户端里的安装器无法远程修补，这一跳用 USB。

## 0.1.6 发布记录（2026-09-10）

- 应用版本 `0.1.6`，`versionCode` 7。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/v0.1.6`
- 公开仓频道标签：`v0.1.13`（jsDelivr `@latest` 已指向这里）。
- 安装包 asset `554465417`，`apk_sha256` 前缀 `6c5e7969`。
- 覆盖条件：手机已装 `versionCode` < 7。系统页应出现覆盖安装，不应只显示「打开」。
- 游戏会验证更新清单签名、安装包大小和 SHA-256，再打开 Android 系统安装页面。
- 覆盖安装必须让新包的 `versionCode` 大于手机上已装的值。只改版本名会下载成功，但系统页仍显示当前版本并提示“打开”。
- 两个版本使用同一包名和同一长期签名，可覆盖安装并保留应用数据。

公开发布页：

`https://github.com/micjason/xiuxian-releases/releases/tag/v0.1.4`

当前客户端实际使用的地址：

- `0.1.3` 及更早：`https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@main/update.json`
- `0.1.4` 起：`https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@latest/update.json`
- 签名地址与清单同一版本别名，只把文件名换成 `update.sig`
- 安装包：清单里的 `apk_url`，必须是 GitHub Releases Assets API 地址，例如
  `https://api.github.com/repos/micjason/xiuxian-releases/releases/assets/<asset_id>`

国内网络下，Godot `HTTPRequest` 访问 `github.com` 网页下载和 `raw.githubusercontent.com` 经常超时。清单走 jsDelivr，安装包走 GitHub API，并带上 `User-Agent: XiuxianUpdater/0.1`。安装包请求还需 `Accept: application/octet-stream`。

jsDelivr 对 `@main` 按分支缓存，最长约 12 小时，且不能可靠刷新。`update.json` 和 `update.sig` 若不同步更新，游戏会报“更新信息安全校验失败”。`@latest` 走 semver 标签，发布后可以 purge。

发布频道文件时：先把匹配的 `update.json` / `update.sig` 提交到公开仓，再打一个**尚未被 jsDelivr 取过**的更高 semver 标签（例如 `v0.1.10`）。不要先 `gh release create` 再补清单——那样 git 标签会停在旧文件上。jsDelivr 的具体版本号缓存是永久的，打错后不能重用同一个标签。

## 0.1.4 发布记录（2026-09-09）

- 应用版本 `0.1.4`，`versionCode` 5。
- GitHub Release：`https://github.com/micjason/xiuxian-releases/releases/tag/v0.1.4`
- 公开仓频道标签：`v0.1.11`（jsDelivr `@latest` 指向这里，不要复用已取过的版本号）。
- `@latest` 已走通：清单、签名、APK 哈希一致，安装包可下载。
- `@main`（0.1.3 客户端）在 21:40 CST 已刷回可下载的 `0.1.4`：`apk_sha256` 前缀 `a68b9b5b`，asset `552742158`，`apk_http=200`，签名成对。本机按 0.1.3 路径完整下载后哈希一致。
- 不要再 `--clobber` `v0.1.4` 的 `xiuxian.apk`（覆盖会换新 asset id，旧 id 变 404，`@main` 分支缓存可能再次指到死链）。
- `0.1.3` 现在可以点检查更新。USB 备用路径仍是 `tools/release/install_local_apk.sh`；人不在电脑旁时用 `tools/release/wait_and_install_local_apk.sh`。二者都会先核对本机 APK 与 GitHub `main` 清单哈希一致。装完后先截一张保留存档的主界面（核 `0.1.4` / `versionCode` 5），再清空该包数据，尝试用 `run-as` 写入顶 8 小时离线存档（正式包通常写不进应用私有目录，不要把 `Android/data/...` 外部目录当成成功），写不进去则退回短离线，自动拍闭关弹窗并连破前三阶。真机 OCR 必须看到离线文案（闭关/归来/获得修为）和各阶横幅原文（`突破成功 凡人` / `炼气初期` / `炼气中期`），简记里还要有「突破成功」；只看到按钮「突破境界」或路径里的「炼气」不算过。只要截图、不要清档时执行 `CLEAR=0 tools/release/verify_device_playthrough_014.sh`。桌面闭环用 `tools/release/verify_desktop_014.sh`。
- 发布前用 `tools/release/check_update_channel.sh` 确认 `jsdelivr-main matches github-main`。节流未结束时不要 purge。以后发更新用 `tools/release/publish_update_channel.sh`：通道预检失败会直接退出，并且不会 `--clobber` 已有 APK。

## 真机验收记录（2026-09-09）

- 设备：OnePlus PJZ110，Android 16，USB 调试已授权。
- USB 安装 `0.1.0` 后，页面显示版本 `0.1.0`，本地数据标记为“首次安装 0.1.0”。
- 游戏内检查更新成功提示“发现新版本 0.1.1”，下载到 100%。
- 系统弹出安装未知应用/覆盖安装确认页；ColorOS 完成页显示来自“修仙”、版本 `0.1.1`。
- `adb dumpsys package com.micjason.xiuxian`：`versionName=0.1.1`，`versionCode=2`。
- 再次打开游戏：显示“0.1.1 更新版已启动”，数据标记为“首次安装 0.1.0（已保留）”，状态为“当前已是最新版本。”

## 首次真机验证

1. 用 USB 数据线连接 Android 手机，并在手机上允许这台电脑调试。
2. 通过本项目外接盘 `adb` 安装 `builds/development/0.1.0/xiuxian.apk`。
3. 打开“修仙”，确认显示版本 `0.1.0` 和“首次安装 0.1.0”数据标记。
4. 等待更新提示，点击“下载更新”。
5. 首次使用时，在 Android 设置页允许“修仙”安装未知应用，返回游戏后点击“继续安装”。
6. 在 Android 系统安装页确认更新。部分 ColorOS/OriginOS 机型按钮文案是“完成”，不是“安装”。
7. 再次打开，确认版本是 `0.1.1`、页面出现更新版标记，并且原数据标记显示“已保留”。

普通 Android 应用不能跳过第 5、6 步，也不能静默安装。APK 必须包含 `game/assets/security/update_public.pem`，否则会提示“更新信息安全校验失败”。

## 构建命令

当前 `project.godot` 和 `export_presets.cfg` 的版本必须一致：

```sh
tools/release/build_android.sh \
  0.1.1 \
  /Volumes/kaixia/projects/xiuxian/builds/development/0.1.1/xiuxian.apk
```

脚本从 macOS 钥匙串读取密码，不会把密码写入源码或日志。Godot 导出路径必须是绝对路径。

## 发布文件

先把 APK 上传到公开仓库 Release，再使用该资源的 GitHub API 地址生成清单：

```sh
tools/release/create_update_manifest.py \
  --apk builds/development/0.1.1/xiuxian.apk \
  --version 0.1.1 \
  --version-code 2 \
  --apk-url "https://api.github.com/repos/micjason/xiuxian-releases/releases/assets/<asset_id>" \
  --release-notes "更新说明" \
  --private-key /Volumes/kaixia/GodotDev/xiuxian/signing/update-private.pem \
  --output-directory builds/development/0.1.1/release-assets
```

也可用 `tools/release/publish_update_channel.sh` 一次做完预检、建新 Release、签名清单和频道标签。`@main` 下载 404 时会拒绝发布。

`update.json` 和 `update.sig` 需要同时：

1. 上传到对应 GitHub Release；
2. 提交到 `micjason/xiuxian-releases` 的 `main` 分支，并打新的 semver 标签供 `@latest` 读取。

发布文件名必须固定为 `xiuxian.apk`、`update.json` 和 `update.sig`。`apk_url` 每次上传后会得到新的 `asset_id`，不能沿用网页下载链接。

## 密钥安全

- Android 长期签名和更新清单私钥位于 `/Volumes/kaixia/GodotDev/xiuxian/signing/`。
- 私钥和安装包不进入源码 Git。
- Android 签名证书 SHA-256：
  `10:5D:D1:57:D7:4B:9D:53:D8:BA:00:8D:6E:6B:3C:5C:61:09:BE:9C:99:6F:C1:DA:A9:DA:7D:2C:64:BF:4E:BA`
- 更新公钥 SHA-256：
  `e9f0c958d2e43d93a2c3fdd1be8344b7cea75082589d5467a85925c99622aeb3`

签名文件损坏或丢失后，已安装应用将无法正常覆盖升级。完成首次真机验证后，应将签名目录加密备份到另一处安全位置。

## 隔离边界

所有本项目新增 Android 工具与缓存位于 `/Volumes/kaixia/GodotDev/xiuxian/`。电脑原有 Android/iOS 工具、工程、证书和配置未被删除、移动或修改。
