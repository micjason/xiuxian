# 修仙（xiuxian）

一款 Android 优先、竖屏、2D 单机放置修仙游戏。首个可玩闭环是：

`挂机获得修为 → 突破境界 → 提高修炼效率`

当前阶段只建设项目规范、架构文档和 AI 工作流，不包含玩法代码。

## 固定环境

- Godot：4.7.2 stable
- Godot 命令：`/Volumes/kaixia/GodotDev/bin/godot`
- 仓库：`/Volumes/kaixia/projects/xiuxian`
- Godot 工程根目录：`game/`（创建工程后）
- 首发平台：Android
- 脚本语言：强类型 GDScript

启动开发前必须确认外接硬盘挂载在 `/Volumes/kaixia`，Godot 运行期间不得拔盘。

## 目录职责

- `.cursor/rules/`：长期生效、按文件范围加载的项目约束。
- `.cursor/skills/`：可重复调用的设计、实现、验证和发布流程。
- `game/`：Godot 可导入的运行时工程；只放游戏真正需要的文件。
- `content-source/`：PSD、工程源文件、未筛选音视频等原始素材，Godot 不扫描。
- `docs/`：产品、架构、美术、运营和 ADR 决策记录。
- `tools/`：自动化与校验工具。
- `backend/`：远程清单或服务的预留目录；首期不实现业务后端。
- `builds/`：本机构建产物，不进入 Git。

## 协作原则

1. AI 可在已确认范围内自主修改、验证并按里程碑提交。
2. 产品范围变化、破坏性数据迁移、发布和密钥操作必须先确认。
3. 每项功能先写验收标准，再实现，再运行与风险相匹配的验证。
4. 大型二进制文件按 `.gitattributes` 使用 Git LFS；密钥、签名文件和构建产物不得提交。
5. 重要技术决定写入 `docs/decisions/`，不要只保留在聊天记录中。

详细边界见 `docs/product/mvp-scope.md`，开发时遵循 `.cursor/rules/`。
