# 目录布局

```text
xiuxian/
├── .cursor/
│   ├── rules/                 # 长期项目约束
│   └── skills/                # 可重复 AI 工作流
├── game/                      # 未来 Godot 工程根目录
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
├── docs/                      # 产品、架构、美术、运营、ADR
├── tools/                     # 自动化与验证工具
├── backend/                   # 远程能力预留，首期为空
└── builds/                    # development、release，本地生成且忽略
```

## 边界

- Cursor 打开仓库根目录 `xiuxian/`，Godot 只打开 `xiuxian/game/`。
- 可被游戏加载的优化后素材放 `game/assets/`；原始或候选素材放 `content-source/`。
- `game/resources/config/` 放运行时配置，玩法规则代码不得硬编码其重复副本。
- 构建输出只进入 `builds/`，不放在 `game/`，不提交 Git。
- 后端或发布基础设施确定前只保留 `backend/` 边界，不提前选择技术栈。

空目录不会被 Git 保存；当前骨架用于本机规划，后续由真实工程文件自然固化。若需要从空仓库复建，可按本文件创建。
