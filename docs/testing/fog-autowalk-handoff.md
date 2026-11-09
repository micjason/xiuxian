# 迷雾已知区域自动行走：交付与复查说明

## 边界
- 基于 `origin/dev2@2c6f24ac`（含#69 `49187b6d`），独立 `/workspace/xiuxian-ui-fog-autowalk`，分支 `proto/fog-known-autowalk`。
- 本地提交而已：未push、未合入、未部署、未打APK、未改latest/tip/版本；没有CloudAgent或任何对外消息。
- 主仓当前分支和旧697改动工作树未动。测试库是新PG16实例55439，只有该实例的隔离测试库使用withDb清表；共享5432未连接。

## 协议与兼容
- 新GET fog增加 `protocol: fog-step-v1` 和64位状态摘要 `revision`。该摘要是当前DTO的ETag，不是单调计数；完整stepId终态账本才是取消保证。
- 新move body：`{protocol,stepId,x,y,expectedFrom:{x,y},expectedRevision}`。旧`{x,y}`/`r,c`及原幂等header接口保留。
- 返回`{fog: 当前权威状态,step:{id,status: committed|cancelled|rejected,error?}}`。业务拒绝也是200+rejected；格式/协议/异体key错误400。重放同stepId返回其终态与当前状态，非历史位置快照。
- POST同地图`/reconcile`传原move body。在玩家行锁下，已执行读取终态；未执行写cancelled墓碑。迟到原POST只能看到该终态，不能再移动。reconcile不产生移动扣费。
- 新前端没看到新协议明确停止提示，不降级到旧move。网络不明保留pending；下一次明确操作/重新进图先终态对账，期间不发新move。离页不发新的move或后台重试。
- 改动仅fog模块；未重构loop/withIdempotency，旧接口既有泛用幂等行为不冒充已全面修复。

## 20项实际验收矩阵
以下“通过”指对应自动化层的断言通过；不是20项都做了安卓/手工实玩。HTTP测试是Fastify真实路由+独立PG，延迟用明确闩锁与玩家行锁；截图是PC Godot/Xvfb真实渲染、真实本地TCP API，程序调用实际点击处理器，不是安卓实拍。

| # | 实际结果 | 实跑证据 |
|---|---|---|
| 1 | 通过：U形墙直距2，四向最短绕障6步，不截3/5格 | GUT test_fog_route::test_u_wall_uses_shortest_detour_not_three_or_five_limit |
| 2 | 通过：可见孤岛被未知格隔断，拒绝且0 POST | GUT test_fog_route::test_visible_island_and_unknown_adjacent_rejected |
| 3 | 通过：未知相邻/远点均拒绝；已揭边缘继续揭雾 | 同上；GUT legacy_backend_and_unknown；07_unknown_rejected.png；新局5→79真实行走 |
| 4 | 通过：途中新揭雾不扩快照，不抄新近路 | GUT test_new_reveal_does_not_shorten_route_through_out_of_snapshot_cell（6步、不走新2,1） |
| 5 | 通过：箱/怪/事件不可穿越；目标停最短合法邻格 | GUT planner living_objects/object_target；UI monster_and_event_targets；08_unreachable_rejected.png |
| 6 | 通过：最后一步响应后动画中取消，不弹旧框、不交互 | GUT test_cancel_during_animation_does_not_show_object_or_continue（箱目标一格到达） |
| 7 | 通过：擦过旁边怪不误交互；已完成物件可过 | GUT test_completed_objects_passable_and_incidental_adjacent_monster_not_triggered |
| 8 | 通过：同目标连点20次只一条串行路线 | GUT test_far_walk_and_twenty_repeated_clicks_are_one_serial_route（4成功步、余额20→16、max1） |
| 9 | 通过：在途改目标等旧步终结，从权威位置重算 | GUT test_new_target_waits_for_inflight_and_replans_from_authority；max1 |
| 10 | 通过：动画期间改目标/取消不得恢复旧队列 | GUT test_new_target_during_animation_waits_and_never_resumes_old_queue；FogStop真实按钮测试 |
| 11 | 通过：服务端已提交但响应丢弃，不换key重发移动 | 真实TCP截响应；05/06截图+http-trace.json；UI lost_committed_response测试 |
| 12 | 通过：旧POST延迟时GET先回不是终态，墓碑后迟到0落步 | HTTP steps.test “barriers a delayed original POST”：preHandler闩锁；GET旧位置→reconcile→新move→释放旧POST |
| 13 | 通过：同key并发只一次扣费，异体拒绝 | HTTP steps.test duplicate/stale with player-lock barrier；相同key两响应状态相同；body变目标400 |
| 14 | 通过：同源状态不同key/另一设备只一操作成功 | 同上，两个不同stepId状态一committed一rejected，余额只199 |
| 15 | 通过：资源不足/配置每步2不超扣 | GUT budget1走1步；HTTP configured cost2 balance1拒绝、余额仍1 |
| 16 | 通过：权威返回坐标不符/旧重放不可假动画或覆盖新状态 | GUT wrong_authority_position；HTTP committed response replay after newer step返回当前pos3,8，不回3,9 |
| 17 | 通过：离页在途最多落一步，不续、不弹、重进不复活旧路 | GUT hide_during_request/hidden_unknown_step（重进只reconcile，不move）；04_cancelled.png |
| 18 | 通过：入口晚GET不能拉回；换账号晚响应不绑定 | GUT test_late_entrance_get_does_not_pull_user_back_from_another_page + account_change；显式战斗晚响应也不重开；重进等待未结束交互，多个入口等待者只做一次终态对账 |
| 19 | 通过：GET跨日/首次建档/旧预算升级并发保持余额进度 | HTTP locked GET用pg_blocking_pids确认真锁等待；two first GETs仅一行；legacy upgrade+chest并发197点且opened/marker均保留 |
| 20 | 通过：谷口未满站格拨雾不战；满后确认；全79/79 | HTTP guard78→79；09/10/11截图；真实新局5/79→79/79，43次独立目标、60步移动+3次显式开箱、200→140，13截图 |

另有新增权威物件落在原路径时停止、不私自绕过/选择事件，以及JSON原始类型move body返回400而非500的回归测试（均已观察红→绿）。

## 证据位置
- 图片与脱敏HTTP步骤记录：`/workspace/cp_fix_shots/fog_autowalk/`。01/02/03前/途中/到达；04取消；05/06丢响应/恢复；07未知；08不可达；09/10/11谷口；12/13新局完整探索；14正常主场景真实API“洞府→迷雾→移动→返回”集成图（normal-main-smoke.log）。
- 真实远路：8步，200→192，抵达(6,5)；取消只派1步，200→199；丢响应后同stepId对账再走新目标共2步，200→198。trace max_inflight=1。
- 新局43条独立目标，每条仅自己的点击快照；共60成功移动+3次用户确认开箱，5/79→79/79，200→140。不是产品自动扫图功能。
- 所有原始日志：`/workspace/.deploy/fog-autowalk/`。包括backend-red、planner-red、ui-red、nav-red、stop-button-red、interaction-red、new-blocker-red以及最终green日志。测试工具会有引擎断言退出码为0的情形，因此截图验收同时检查日志无SCRIPT ERROR、13张核心图齐全与trace最终79（另有14正常主场景集成图），不单看exit code。
- 全量GUT有既有红项，基线归档同环境对照，不宣称全绿。精确计数及同名失败比较在`verification-summary.json`与`godot-baseline-comparison.json`（同目录）。

## 最终实跑计数
- 后端130文件、513/513通过（退出0）；见独立测试库的`backend-final-full.log`。类型检查与全库ESLint退出0。
- GUT针对性34/34，130断言；全量389项中366通过、23失败（退出1）。基线361项中338通过、23失败；23项失败名逐个完全一致，无新增失败。仍不宣称全量全绿或可免复核上线。
- 14张PC真实渲染截图（含正常主场景集成），SHA256清单齐全；20反例逐条结果见上表及JSON。

## 可复现命令（不使用npm test默认共享配置）
工作目录均为本工作树。
```sh
# 现有私有实例；如果停了，使用自己的目录启动，不操作共享PG。
/workspace/pg16/root/usr/lib/postgresql/16/bin/pg_ctl -D /workspace/.deploy/fog-autowalk/pg -l /workspace/.deploy/fog-autowalk/pg.log -o '-p 55439 -h 127.0.0.1 -k /workspace/.deploy/fog-autowalk' start
cd backend
DATABASE_URL=postgres://box@127.0.0.1:55439/xiuxian_fog_autowalk_test node_modules/.bin/vitest run --maxWorkers=1
node_modules/.bin/tsc --noEmit
node_modules/.bin/eslint src/modules/fog/{steps.ts,steps.test.ts,routes.ts,actions.ts} src/scripts/fog-autowalk-local.ts
# 本地fixture API只允许下面这个专属数据库；18082已有共享进程所以使用18083。
DATABASE_URL=postgres://box@127.0.0.1:55439/xiuxian_fog_autowalk_local FOG_AUTOWALK_LOCAL=1 LOG_LEVEL=silent node --import tsx src/scripts/fog-autowalk-local.ts
```
另一个终端：
```sh
cd /workspace/xiuxian-ui-fog-autowalk
HOME=/workspace/.deploy/fog-autowalk/targeted-home XIUXIAN_UI_MOCK=1 XIUXIAN_UPDATE_CHECK=0 /workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 --headless --path game -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_fog_autowalk.gd -gtest=res://tests/unit/test_fog_route.gd -gtest=res://tests/unit/test_cave_fog_entry.gd -gexit
HOME=/workspace/.deploy/fog-autowalk/final-unit-home XIUXIAN_UI_MOCK=1 XIUXIAN_UPDATE_CHECK=0 /workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
HOME=/workspace/.deploy/fog-autowalk/godot-home XIUXIAN_API_BASE=http://127.0.0.1:18083 XIUXIAN_UPDATE_CHECK=0 xvfb-run -a /workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 --path game --rendering-method gl_compatibility --resolution 1080x1920 res://scenes/dev/capture_fog_autowalk.tscn
```
独立人工复查可在私有API运行时，用同一godot-home（测试会话已存储）打开正常主场景，不设置UI_MOCK：
```sh
HOME=/workspace/.deploy/fog-autowalk/godot-home XIUXIAN_API_BASE=http://127.0.0.1:18083 XIUXIAN_UPDATE_CHECK=0 /workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 --path game res://scenes/main.tscn
```
如需新局，仅对**这个本地fixture实例**执行`curl -s -X POST http://127.0.0.1:18083/__fog_fixture/spawn >/dev/null`；guard/known也可复现对应fixture。不要对线上或共享服务运行。fixture脚本从未导入生产server.ts。

## 只写不执行的上线顺序
1. 负责人独立复查本地SHA与证据，确认既有GUT红项是否影响本次发布。
2. 先部署仅后端fog增量（无schema迁移）。用旧69客户端验证单步/交互/谷口；GET确认新协议，验证reconcile墓碑行为。没有要求现在执行此步骤。
3. 再由负责人按既有流程改版本、升客户端包；本分支未改正式版本号/构建配置。
4. 新客户端遇旧后端明确停止，因此回退后端必须同时考虑客户端能力提示；不能靠静默旧接口维持远路。已有新ledger不被旧代码当combat session读取（endpoint独立）。

## 遗留限制/风险
- PC自动化，不是安卓触摸/弱网真机验证；掉响应是确定性的传输故障注入，不冒称实际切断网络。
- 全量Godot基线本就有23失败和大量资源/孤儿警告，新增针对性用例全通过；此次不顺手修无关洞府、战斗UI或资源生命周期。
- 取消后已发一步仍可能落地，界面明确按权威结果记账；不能宣称服务端撤销已提交移动。
- pending ledger在页节点生命周期内保存，应用重启不会自动恢复旧路线；服务端revision/from拒绝旧延迟步，仍应复查跨设备体验。
- 通用loop幂等没有全域重构；fog新协议使用独立namespace+body绑定，旧接口兼容保留其既有行为。
- 未做独立第三方代码评审（此执行环境没有可用review子代理工具）；需要负责人做既定独立实玩与反驳复查。
