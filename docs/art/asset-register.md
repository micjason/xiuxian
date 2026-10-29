# 素材登记表

新增占位或正式素材时追加记录。没有来源与许可证信息的素材不得进入发布包。

行囊 / 装备出图提示词见 `docs/art/chatgpt-image-prompts-bag.md`。行囊页骨架提示词见 `docs/art/image2-prompts-bag-page-2026-09-13.md`。生成后按本表逐条登记再进包。

## bag_page_temp_2026_09_13

```yaml
id: bag_page_temp_2026_09_13
file: game/assets/images/
type_and_purpose: 行囊页临时背景、立绘、空槽剪影与底栏线标
source: 豆包 image2，用户本地下载后由脚本抠白底、裁水印并改英文名
license: 待确认；仅供本地看效果，未批准前不进发布包
acquired_at: 2026-09-13
budget: 背景 1080x1920 PNG；其余 512 或 1024 透明 PNG
status: 占位
notes: 头盔仍是西式骑士盔；立绘与夜山不是同一套画风。正式版替换后删除本批。
```

## 字段说明

- **ID**：稳定英文标识，与文件名无关。
- **文件**：运行时路径；只有源文件时填写 `content-source/` 路径。
- **类型/用途**：UI、角色、环境、物品、特效、音乐、音效、语音、字体或视频。
- **来源**：作者、网站链接或 AI 模型与生成工具。
- **许可证**：许可证名称、版本、商用/修改/署名/再分发条件。
- **获取日期**：`YYYY-MM-DD`。
- **预算**：像素尺寸、时长、采样率、压缩格式和预估内存。
- **状态**：占位、待审核、已批准、待替换或禁用。
- **备注**：提示词、编辑过程、署名文本和风险。

## app_icon

```yaml
id: app_icon
file: game/assets/art/ui/app_icon.svg
type_and_purpose: Android Demo 应用图标
source: 项目内创建的原创几何图形
license: 项目所有
acquired_at: 2026-09-09
budget: 512x512 SVG
status: 占位
notes: 月亮、山峰与云线构成；正式美术确定后替换
```

## outfit_q_2026_10_29

```yaml
id: outfit_q_2026_10_29
file: game/assets/art/q/outfit/
type_and_purpose: 主角换装整图。战斗 preview_{white,green,blue,purple,orange}.png（1024²），打坐 meditate/ 同名五档，头像 avatar/avatar_{tier}.png 与 avatar_{tier}_round.png（124²）
source: 2026-10-29 美术交付，规格见同目录 OUTFIT_SPEC.md。与既有 Q 版人物同一批生成方式（AI 出图后再处理）
license: 商用/再授权条款尚未确认，与 ASSETS_LICENSES.md 第 8 节 A 类相同
acquired_at: 2026-10-29
budget: 战斗与打坐各约 1MB PNG；圆头像 124² 约数十 KB。无损导入（compress/mode=0）
status: 待审核
notes: v1 只整图替换。分层 base_body/robe 未入库。无 appearance 时游戏仍用 player_fight、打坐动画和 avatar_player_round。
```

## skill_icons_q_2026_10_29

```yaml
id: skill_icons_q_2026_10_29
file: game/assets/art/q/icons/{slash,thunder,fire,heal_circle,ice,wind,poison,gold_light,shield}.png
type_and_purpose: 技能栏与后台列表图标，文件名对齐 fx_type。skill_* 是同图别名
source: 2026-10-29 美术交付，规格见 game/assets/art/q/icons/SKILL_ICONS.md
license: 商用/再授权条款尚未确认，与 ASSETS_LICENSES.md 第 8 节 A 类相同
acquired_at: 2026-10-29
budget: 256² PNG，单张约 80–110KB
status: 待审核
notes: 后台副本在 admin/public/skill-icons/。不包含战斗施法序列帧。
```

## 登记模板

每项素材使用一个二级标题并复制以下字段：

```yaml
id: stable_asset_id
file: game/assets/example.png
type_and_purpose: UI 占位图
source: 项目自制
license: 项目所有
acquired_at: 2026-09-09
budget: 512x512 WebP
status: 占位
notes: 无
```

