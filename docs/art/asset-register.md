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

## breakthrough_tribulation_2026_10_22

```yaml
id: breakthrough_tribulation_2026_10_22
file: game/anim_q/breakthrough_tribulation/
type_and_purpose: 突破成功「天雷渡劫」特效（约 10 秒）：场景、脚本、雷电/云/金光贴图、横幅绶带
source: 2026-10-22 天雷渡劫交付包；部分贴图与 game/anim_q/breakthrough/ 同名文件字节相同
license: 特效图按既有突破特效登记为项目程序生成、可商用；横幅字体不另存，改指 assets/fonts/ZCOOLQingKeHuangYou-Regular.subset.woff2（SIL OFL 1.1）。逐文件见 game/assets/art_q_license_list.csv
acquired_at: 2026-10-22
budget: PNG 合计约 1.4 MB（最大单张 fx_magic_circle 512×512，约 312 KB）；落雷约 220×520；节点约 40，CPUParticles2D，无 Spine
status: 已接入突破成功路径
notes: 未提交预览 mp4。未使用的 fx_pillar.png、fx_ripple.png 是旧图副本。交付自带的 8 MB 庆科黄油体 TTF 不入库。
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

