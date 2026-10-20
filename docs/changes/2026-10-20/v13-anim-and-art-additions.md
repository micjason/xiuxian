# 2026-10-20 v13：动画特效 + 美术补充（0.13.0 / 33）

动画交付：`/workspace/anim_out_q/`（README.md，成鹏确认的 5 个动画）；美术补充：`/workspace/art_out_q/`（`_preview_additions.png`、SPEC_Q.md 第 12 节）。
入库：`tools/art/install_q_art.py`（新增 `--anim`，动画整夹拷到 `game/anim_q/`），结果 `assets/art/q/CHECK.txt`：nine-slice 73、占位 0、动画文件 79、问题 0。

## 范围（只改现有功能 / 界面，不加玩法，数字全部来自玩家状态 / 配置）
- **主角**：所有地方换成拆层拼合主角（双手搭膝，`anim_q/hero_meditate`，打坐 idle 自动循环）。新组件 `scripts/ui/fx/q_hero.gd`（QHero）：修炼页（带灵气 / 法阵 / 光点）、历练场景、背包纸娃娃、战斗页（只要人物）、突破弹窗（莲台上，隐藏坐垫）、突破成功弹窗。静态图 `sprites/hero_meditate.png` 改为由拼合图裁出（只在动画缺失时兜底）。
- **突破圆钮**：底栏中间换成 `ui_break_orb`：可突破时呼吸光 + 星光（idle），条件不够淡化、圆满变灰；按下 / 松开动画。
- **按钮 / 弹窗**：离线弹窗、突破弹窗、突破成功弹窗用 `ui_popup` 的 open / close；「领 取」用 `ui_button_bounce` 场景，其它按钮（双倍领取、突破、继续修炼）用 `QFx.bounce` 照同样关键帧做回弹。
- **飘字 / 掉落**：每次结算在修炼页主角头上飘真实的挂机修为（540,720），击杀修为（780,560，金色）；掉落物（最多 3 件）从掉落行飞进底栏背包，背包图标跳一下。
- **突破特效**：点「突破」→ 充能 2s → 成功（光柱、光环、星光、「突破成功」横幅 2.4s）→ 结算弹窗。失败 / 出错照旧提示。
- **横幅位置修正**：横幅原来在 (0,-360)，压住弹窗顶部的境界行和左右「战力提升 / 成功率」；改到主角脚下的莲台（y=0，此时充能条已淡出），并把前景层 z 抬到 30（不被主角盖住）。GUT 校验横幅矩形不和 RealmRow / PowerGain / RateRing 相交、在舞台内。突破成功弹窗：绶带「突破成功」单独一行，下面换成新舞台（主角 + 莲台 + 光效），不再用旧的墨色头图。
- **开箱**：离线弹窗宝箱换成 `chest_open` 场景（关着 → 开盖金光喷金币 → 打开后待机），下面的总数从 0 滚到真实总数（滚完显示精确值）。没有动画时退回新交的 `sprites/chest_open.png`。
- **提示条**：「功能暂未开放」换成美术 `ui/toast_bg`（奶白胶囊，Bold 34 #4A3A33，最小宽 420、高 96，居中 y≈1500，淡入 0.2s 上浮 12px → 停 1.5s → 淡出 0.3s）。普通提示（操作结果 / 错误）不变。
- **头像**：顶栏头像换成 `ui/avatar_player_round@2x.png`（`icons/avatar.png` 也换成美术头像），不再裁 hero_meditate 的头。
- **怪物**：幽冥古道 / 赤炎火山 8 只（游魂、骨傀、血蝠、噬魂老鬼、炎鳞蜥、火鸦、熔岩傀、赤焰蛟）入库 `sprites/mon_*`；`ArtLib.MONSTER_KEYS` 按名字查，「老鬼 / 噬魂」排在「魂」前面；火鸦 / 炎鳞蜥 / 赤焰蛟原图朝左不翻转。历练场景不再写死 `mon_snake`，按当前关卡怪物名查；战斗页首领也用 Q 版立绘。
- **绘制层级**：动画部件自带 z_index（主角最高 20、飘字 50），外壳各层显式抬高：顶/底栏 30 < 特效层 60 < 突破弹窗 100 < 其它弹窗 200 < 提示条 300。

## 和 README 不一样的地方
1. **字体没有照原样拷**：交付每个文件夹自带一份 ZCOOL QingKe HuangYou（8 MB）和 ZCOOL KuaiLe（1.5 MB），一共重复 3 份。入库脚本不拷 `font/`，场景里的字体引用改指 `assets/fonts/` 的共用子集：快乐体用现有子集，庆科黄油体新做子集（快乐体子集字表 + ASCII，约 0.9 MB），OFL 文本 `fonts/OFL-ZCOOLQingKeHuangYou.txt`。
2. **突破横幅位置**：见上（README 默认 y=-360 会压标题区）。
3. **开箱示例数字隐藏**：`chest_open` 场景里的 Number（示例滚动数字）不显示，真实总数由弹窗里原来的 TotalLabel 滚动，避免两个数字。
4. **按钮回弹**：只有「领 取」直接用 `ui_button_bounce` 场景；其它按钮保留原样式，只套同样的按下 / 回弹关键帧（`QFx.bounce`）。
5. **圆钮**：`ui_break_orb` 自带的 Hit 按钮不用（点击仍由原来的 QBreakButton 接，状态逻辑不变）。
6. **修炼页飘字**：只飘修为数字（真实结算值），击杀 / 掉落文字仍在下方卡片里；主角「点一下睁眼」（peek）没有接。
7. 修炼页挂机宝箱保持原来的关着的宝箱（SPEC 12.2，功能暂未开放）。

## 授权
- `art_q_license_list.csv` 322 行 = 美术 `license_q.csv` 244 行 + `tools/art/q_license_extra.csv` 78 行（开箱拆层 1、`anim_q/` 77、庆科黄油体子集 1）。动画文件按来源分：主角 / 宝箱拆层图、hero_glow、示例掉落图标 = A（AI 生成，条款待确认）；`*/fx/*`（gen_tex.py）、与 `art/q/ui` 相同的切图、圆钮拆层 = B（自有）；场景 / 脚本 = 自有代码。
- ASSETS_LICENSES.md 第 8 节更新行数、补第二批美术和字体，新增 8.1 动画交付；credits.json 字体组加 ZCOOL QingKe HuangYou、美术组加动画说明。

## 测试
- 新增 `tests/unit/test_q_fx.gd`（13 个）：5 个动画场景都在；主角全部换成动画（修炼 / 历练 / 背包 / 战斗 / 突破弹窗坐垫隐藏），没有地方再用静态主角图；修炼页主角锚点 x=540、1 倍；顶栏头像；圆钮只在可突破时闪；横幅不压标题区；充能 → 成功 → 结算顺序、结算标题不压境界名；开箱停在打开、总数滚到真实值、示例数字不显示；飘字是真实结算值并会清掉；掉落飞进背包、背包跳；8 只新怪物名字映射和翻转；配置里所有小怪都有 Q 版立绘；`anim_q/` 和新美术每个文件都有授权行。
- 改：离线领取 / 链路 2 等关闭动画（0.35s）；链路 3 等特效播完（最多 8s）出结算；离线开箱改查动画；「领取」文字按 claim_text。
- GUT 212/212（`-gfailure_error_types=gut,push_error`，原因同前：GUT 字体是 LFS 指针）。
- 截图：`/workspace/ui_preview_v13/`（7 屏 q_* + 特效关键帧 fx_*，`v13_sheet.png`），脚本 `scripts/dev/capture_v13.gd`（`/workspace/tools_ui/cap13.sh`）。xvfb 软件渲染下动画按真实时间播，关键帧可能差一两帧。

## 上线 0.13.0（33）（时间均为 Asia/Shanghai）
- 12:22 `tools/deploy/release_apk.sh --version-name 0.13.0` 导出签名（固定密钥，证书 SHA-256 与 0.12.0 相同，aapt2 核对包名 / 版本）；中途被打断，没有重导、没有再升版本。13:00 左右用 `tools/deploy/deploy.sh publish-apk /workspace/.deploy/apk/publish-33` 上传发布（只动 dev2：/opt/xiuxian-dev2、端口 8090；后端没有改，没有跑迁移、没有重启服务）。这次上传带宽只有约 20 KB/s，100 MB 传了约 32 分钟。
- 外部核对：`/healthz` ok；`/download/latest.json` versionCode 33 / 0.13.0、sha256 `db11b74798c1029228a459d98b6ecaaab92c3405be059a14aa87ef25ffa90d4f`、size 100231178，和本地一致；外网下载的 APK sha256 一致；后台首页（`/`）加载正常、无页面错误（`/workspace/ui_preview_v13/real/admin_login.png`）；客户端假装 0.12.0（32）连线上服务器弹出「发现新版本 0.13.0」（`real/update_popup.png`）。

## 上线后发现的问题（已在本地修，**未发布**）
- `real/update_popup.png` 里看到：**未登录时主界面（顶栏、主角、底栏圆钮）画在登录页上面**。原因是本次给外壳各层抬了 z_index，登录页还是 0。修复：登录页 z = 150（主界面各层之上、弹窗 / 提示条之下），GUT 加 `test_login_page_covers_the_whole_main_ui`，修后截图 `real/update_popup_after_login_fix_local.png`。GUT 213/213。
- 线上 0.13.0（33）包里还是有这个问题（只影响登录页；登录后的界面正常）。要修到手机上需要再发一个 0.13.1（34）：`DEPLOY_HOST=101.132.74.32 tools/deploy/release_apk.sh --version-name 0.13.1`（服务器拒绝同一个 versionCode 覆盖）。
