# 产品改为可上架的多人版本，并固定代理工作流

日期：2026-10-02。

## 决定

产品目标改为可上架、可给多人玩的完整游戏：Godot 客户端、后台管理、后端接口、PostgreSQL。不再把「只做单机离线、只供本机试玩」当作后续开发的边界。

技术选型维持 TypeScript + Fastify、Vue 3 + Element Plus、本机 PostgreSQL。APK 热更仍走现有 GitHub / jsDelivr。修为、战力和突破由服务器计算。详见 ADR-0006。

为了后续改动能追溯，建立 `docs/changes/`：较大改动按日期建目录并写记录。查代码使用本机已安装的 CodeGraph；做功能和修缺陷使用本机已安装的 superpowers 技能。两套工具都不复制进仓库。

## 改了哪些

- 新 ADR：`docs/decisions/0006-online-product.md`。
- 章程、质量门禁、数据规范、代理工作流和修改记录规则。
- 设计、实现、市场调研三项技能里「不能做服务器」的句子。
- 产品边界、目录布局、更新设计、存档设计、长线设计，以及仍写着单机禁令的 ADR 与里程碑文档。这些旧句改为指向 ADR-0006，玩法层次没有推倒。
- 仓库根已执行 `codegraph init`。索引数据库留在本机 `.codegraph/`，不提交。

## 还没做

- 阿里云还没买，没有公网 IP。
- `backend/` 和 `admin/` 只有说明，没有接口和页面。
- 已发布的 `0.6.3` 客户端仍在手机本地结算。
- 旧的本地存档如何并入账号，还没定。
- CodeGraph 这一版索引不到 GDScript。客户端代码仍要直接读 `game/` 里的脚本。后端 TypeScript 写出来之后再执行 `codegraph sync`。
