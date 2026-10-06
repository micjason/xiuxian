# 目录布局

```text
xiuxian/
├── .cursor/
│   ├── rules/                 # 长期项目约束
│   └── skills/                # 可重复 AI 工作流
├── game/                      # Godot 工程根目录
│   ├── assets/
│   │   ├── art/               # UI、角色、环境、物品、特效
│   │   ├── audio/             # 音乐、音效、语音
│   │   ├── fonts/
│   │   ├── localization/
│   │   └── video/
│   ├── resources/             # 配置与主题
│   ├── scenes/                # core、ui、features
│   ├── scripts/               # core、autoload、ui、features
│   └── tests/                 # unit、integration
├── content-source/            # 原始图片、音频、视频、字体
├── docs/                      # 产品、架构、美术、运营、ADR、changes
├── tools/                     # 自动化与验证工具
├── backend/                   # 玩家接口、结算与发布，见 ADR-0006
├── admin/                     # 后台管理页面，见 ADR-0006
└── builds/                    # development、release，本地生成且忽略
```

## 边界

- Cursor 打开仓库根目录 `xiuxian/`，Godot 只打开 `xiuxian/game/`。
- 可被游戏加载的优化后素材放 `game/assets/`；原始或候选素材放 `content-source/`。
- `game/resources/config/` 放运行时配置，玩法规则代码不得硬编码其重复副本。
- 构建输出只进入 `builds/`，不放在 `game/`，不提交 Git。
- `backend/` 与 `admin/` 的技术选型以 ADR-0006 为准。两目录尚未实现可运行程序。
- Godot 不打开 `backend/` 和 `admin/`。

CodeGraph 索引在本机 `.codegraph/`，由该目录自带的忽略规则排除数据库，不提交索引本身。
