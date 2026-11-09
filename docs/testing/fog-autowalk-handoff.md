# 迷雾已知区域自动行走：交付与复查说明

## 边界
- 基于 `origin/dev2@2c6f24ac`（含#69 `49187b6d`），独立 `/workspace/xiuxian-ui-fog-autowalk`，分支 `proto/fog-known-autowalk`。
- 本地提交而已：未push、未合入、未部署、未打APK、未改latest/tip/版本；没有CloudAgent或任何对外消息。
- 主仓当前分支和旧697改动工作树未动。本次修复只使用私有PG55439的独占`xiuxian_fog_restart_test`；但此前513次全量命令误用了`npm test`，脚本覆盖DSN并连接共享5432测试库，见下面事故更正，撤回“从未连接共享5432”的旧说法。

## 协议与兼容
- 新GET fog增加 `protocol: fog-step-v1` 和64位状态摘要 `revision`。该摘要是当前DTO的ETag，不是单调计数；持久化原stepId并完成终态对账才是本客户端重启取消保证；不是跨设备全局取消栅栏。
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
- 图片与脱敏HTTP步骤记录：`/workspace/cp_fix_shots/fog_autowalk/`。01/02/03前/途中/到达；04取消；05/06丢响应/恢复；07未知；08不可达；09/10/11谷口；12/13新局完整探索；14是旧e8513199的正常主场景连接**fixture服务**“洞府→迷雾→移动→返回”图（normal-main-smoke.log），不是正常server.ts+自然新账号完整链路，也不是本次修复版独立验收。
- 真实远路：8步，200→192，抵达(6,5)；取消只派1步，200→199；丢响应后同stepId对账再走新目标共2步，200→198。trace max_inflight=1。
- 新局43条独立目标，每条仅自己的点击快照；共60成功移动+3次用户确认开箱，5/79→79/79，200→140。不是产品自动扫图功能。
- 所有原始日志：`/workspace/.deploy/fog-autowalk/`。包括backend-red、planner-red、ui-red、nav-red、stop-button-red、interaction-red、new-blocker-red以及最终green日志。测试工具会有引擎断言退出码为0的情形，因此截图验收同时检查日志无SCRIPT ERROR、13张核心图齐全与trace最终79（另有14正常主场景集成图），不单看exit code。
- 全量GUT有既有红项，基线归档同环境对照，不宣称全绿。精确计数及同名失败比较在`verification-summary.json`与`godot-baseline-comparison.json`（同目录）。

## 最终实跑计数
- 旧e8513199的513与GUT34口径不是本次修复版结果。修复版精确结果见`restart-verification-summary.json`及下列新日志；旧`backend-final-full.log`保留，但其513次运行误连了共享测试库，不能作为私有库执行证明。
- 历史e8513199：针对性34/34、全量366/389、23失败。本次最终针对性48/48、193断言；全量403项380通过23失败（exit 1）。基线361项338通过23失败，23个失败名称逐项完全一致，无新增失败；始终不宣称全量全绿或免独立复核上线。
- 本次后端130文件517/517（含16项fog协议及3项真实进程）、tsc与全库eslint退出0；日志`restart-backend-full-final-v3.log`首行核验独占库/端口。GUT日志`restart-targeted-final.log.v3`与`restart-godot-full-final-v3.log`；精确失败名对比`restart-baseline-comparison.json`。针对性仍有8孤儿及退出资源泄漏警告，不冒称没有所有engine ERROR。
- 旧14张PC真实渲染截图（含fixture正常主场景集成），SHA256清单齐全；20反例逐条结果见上表及JSON。它们不是修复版新截图。

## 可复现命令（不使用npm test默认共享配置）
工作目录均为本工作树。
```sh
# 现有私有实例；如果停了，使用自己的目录启动，不操作共享PG。
/workspace/pg16/root/usr/lib/postgresql/16/bin/pg_ctl -D /workspace/.deploy/fog-autowalk/pg -l /workspace/.deploy/fog-autowalk/pg.log -o '-p 55439 -h 127.0.0.1 -k /workspace/.deploy/fog-autowalk' start
cd backend
DATABASE_URL=postgres://box@127.0.0.1:55439/xiuxian_fog_restart_test FOG_RESTART_GODOT=/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 node_modules/.bin/vitest run --maxWorkers=1
node_modules/.bin/tsc --noEmit
node_modules/.bin/eslint .
# 本地fixture API只允许下面这个专属数据库；18082已有共享进程所以使用18083。
DATABASE_URL=postgres://box@127.0.0.1:55439/xiuxian_fog_autowalk_local FOG_AUTOWALK_LOCAL=1 LOG_LEVEL=silent node --import tsx src/scripts/fog-autowalk-local.ts
```
另一个终端：
```sh
cd /workspace/xiuxian-ui-fog-autowalk
# 必须先运行下文标准 --editor --import；不要直接用未导入的干净源码跑GUT。
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
- 旧“pending只在页内、重启靠revision/from”的保证不成立，已撤回。修复版使用发送前可靠写盘的持久化pending及终态对账，应用重启不续旧路线。仍不承诺删除应用数据、卸载、同一user://同时多进程写入等场景。
- 通用loop幂等没有全域重构；fog新协议使用独立namespace+body绑定，旧接口兼容保留其既有行为。
- e8513199已经负责人及独立审查判NO-GO；本次修复SHA仍待他们独立复查，不以执行者自测替代。

## 23:27审查后修复：持久化与跨午夜
### 最小实现范围
- 新`FogPendingStore`只保存fog步骤，不保存路线、token或密码：服务端地址摘要、经当前session验证的playerId、地图、原始body/stepId/protocol、move/reconcile路径；每账号地图保留独立槽。
- 原登录的token/account是两个独立文件，不能信任旧缓存playerId。每新页面/进程或token/地址变化，先GET `/me/account`核实实际actor，才读该账号未决槽；网络失败冻结。A→B不拿B token对账A；回A再对账，不丢A槽。
- 写临时文件、flush、**文件fsync**、同目录原子rename、**目录fsync**、字节读回校验全部成功后才发move。Linux用GNU sync的文件参数（不作全机sync）；目录链同步到HOME。Android用系统toybox fsync并同步应用目录父项。没有持久化能力/返回非零即停止，不以flush冒充fsync。
- 收到合法终态且完整当前权威fog后，将终态+权威状态与pending=false一次原子写盘成功，才释放内存pending。清理失败不继续；即使rename后文件“看似已清理”、目录fsync失败，也必须重新同stepId对账并可靠写盘。
- 损坏JSON/校验和/身份路径异常/只有半写tmp，都冻结保留，不当成无pending。首次写盘失败留下孤立tmp可能需维护处理，不自动删除猜测。暂存记录不构成自动续路。
- 地址别名可能对应同一后台：同一已验证playerId在另一个地址还有未决槽时，明确冻结，要求回原地址对账，绝不跨地址发送原body/凭据。
- 后台仅把预算刷新判断从“不相等”改为“保存日<请求日”，旧now即使锁前采样、跨午夜排队，也不得回退travelDay退款；保留既有now注入/调用签名，不重构loop。
- 两个原并发测试均先用pg_blocking_pids证实3个/2个请求实际等待，再放玩家锁，不再立即释放锁冒充争用。

### 新增14个GUT精确用例
1. 销毁页节点后从文件恢复已提交丢响应步骤，先对账。
2. transport派发时journal已落盘；终态保存包含当前坐标且不含token。
3. 发送前fsync失败：0 move。
4. JSON损坏：冻结且不改坏文件。
5. 仅半写tmp：冻结，不当新档。
6. 终态文件同步失败：只重对账，不发新move。
7. rename后目录同步失败：看得见pending=false也不能盲继续。
8. A→B→A保留A未决，token轮换可恢复。
9. 重新计算checksum但端点身份不匹配：拒发送。
10. 当前地图变化：仍只向原步骤地图reconcile端点对账。
11. 返回terminal标签但缺当前权威位置：不清pending。
12. save_token(B)后save_account(B)前崩溃、缓存仍A：验证实际actor B，绝不拿B对账A。
13. 同playerId在另一服务器地址未决：冻结，回原地址才能对账。
14. B写临时记录发生损坏：rename之前校验，原A未决checkpoint字节不变，0个B move。
日志：`restart-targeted-final.log.v3`。原20反例仍由扩大的针对性集合与HTTP套件覆盖；不把新增14项冒称均为安卓实拍。

### 实际独立Godot进程与HTTP闩锁（不是只new页面）
- `steps.test.ts`的3项显式集成用例启动真实Godot子进程，旧进程SIGKILL；新进程使用同HOME从盘读取原token/account，不复用内存、旧页或旧路队列。测试会话配置是私有0600文件，不入repo、不打印。
- 迟到原POST停在真实HTTP preHandler闩锁：杀旧进程→新进程恢复原stepId并写cancelled墓碑→放旧POST，实际响应cancelled、200点/原位零落步→明确新目标仅1步到199，原stepId账本唯一，前后进程生成新stepId不重复。
- 已提交但丢响应：杀旧进程；关闭本地API，新进程真实连接失败且pending仍在；重建同端口API，另一新进程从原磁盘session进入**正常main.tscn的_open_fog恢复入口**，reconcile读committed，仍只扣1步199，终态+当前权威状态存盘后清pending，不自动发新move。
- A旧POST保持闩锁；新进程只换token到B、故意保留A账号缓存，验证/me/account actor B，不创建B名下的A stepId墓碑、不清A；再重启回A，终态取消旧POST，最终仍200原位。
- 这是Fastify真实HTTP路由+私有PG+fixture内容，不是正常server.ts自然注册完整验收。正常主场景入口也不等于正常生产后台完整链路。实际关闭的是本地API监听，不冒称手机无线断网/掉电实测。
- 红证据：`restart-node-red.log`、`restart-process-red.log`（旧进程杀死后新进程没有墓碑）、`midnight-red.log`、`restart-auth-identity-red.log`、`restart-endpoint-red.log`、`restart-authority-red.log`。
- 绿证据：`restart-http-auth-final.log`（16项协议/真实进程）及`restart-backend-full-final-v3.log`；稳定脱敏副本见`restart-evidence/`，原始随机目录仍保留。独立审查原counterexamples.mts/log未修改。

### 资源导入环境（不掩盖33/34）
- 已核实两张源PNG未坏、未改。HEAD里icon_lingmu/icon_kuilei的.import引用旧短缓存名，本机这些ctex不存在；标准Godot4.7 `--headless --editor --import`生成真实新缓存及对应元数据后，晚入口GET用例与扩大的针对性测试通过，日志没有SCRIPT ERROR/engine import错误。
- `restart-resource-import-evidence.json`同时保留HEAD旧引用不存在、标准导入新路径存在的证据。**不人工做ctex别名、不拿占位资源假装原图。**
- 为不提交无关资源，交付会还原生成的.import元数据；因此独立复跑必须**先标准import，再GUT**。本机最终还原了78项生成元数据差异（实际数量依引擎缓存环境而变），勿误合入，不修改源图。直接对未导入的干净源码跑headless GUT仍可能复现旧资源错误，不能宣称这种环境已绿。
- 命令（仓库根、Godot使用当前盒子二进制）：
```sh
HOME=/workspace/.deploy/fog-autowalk/reviewer-home XIUXIAN_UI_MOCK=1 XIUXIAN_UPDATE_CHECK=0 /workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 --headless --editor --path game --import
# 随后运行上面的GUT命令，或用新的私有HOME；.godot缓存属于本工作树。
cd backend
DATABASE_URL=postgres://box@127.0.0.1:55439/xiuxian_fog_restart_test FOG_RESTART_GODOT=/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 node_modules/.bin/vitest run src/modules/fog/steps.test.ts --maxWorkers=1
DATABASE_URL=postgres://box@127.0.0.1:55439/xiuxian_fog_restart_test FOG_RESTART_GODOT=/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 node_modules/.bin/vitest run --maxWorkers=1
# FOG_RESTART_GODOT不设置时，三项真实进程测试会显式skip，不可冒称也通过。
```

### 负责人自己的独立旧SHA验收
只读引用`/workspace/.deploy/fog_autowalk_owner_verify/REPORT.md`：负责人用正常server.ts:18084、自己的隔离库/自然账号，实走46目标68步5→79、三个显式箱、200→132，护卫只进入战斗未结算。他明确判e8513199 NO-GO，等待修复SHA复测。该服务、库、账号、进程、截图均未由本修复改动；他的旧结果不当作本次修复版通过。

### 必须披露的测试库事故更正
- 2026-11-09 **23:21:33–23:24:40 北京时间UTC+8**，此前513次全量复跑误用`DATABASE_URL=<私有> npm test`。package.json的test脚本又硬编码覆盖DSN，实际连接localhost5432的**共享测试库xiuxian_test**；withDb按既有逻辑TRUNCATE其public测试表。撤回先前“共享5432未连接”的说法。
- 不是线上生产库，但是否影响其他工作使用该共享测试库未知；没有擅自读共享库、恢复或回滚其他人的数据。旧`backend-final-full.log`与原终端记录保留。更早512次运行是direct vitest/private55439，确实隔离，不能混为同一口径。
- 本次修复所有数据库测试均direct vitest，只用新建独占55439/xiuxian_fog_restart_test；完整日志首行current_database/port核验。**不要再运行npm test脚本**。负责人需知悉这次越界事故。

### 新遗留边界
- Android的toybox fsync调用未做真机实测，未知/不支持平台（含未实现的Windows/macOS）明确停走；不是静默退化到不可靠flush。上线前需负责人确认目标Android可用与耗时。
- PC SIGKILL+文件恢复+本地监听关闭是真实进程/网络测试，但不是物理断电、磁盘损毁或安卓触摸实测。文件fsync不能超越硬件谎报写入成功的故障。
- revision仍非单调；跨设备接管/另一设备遗留请求没有共享本地journal，未获得本轮“同一存档重启”取消保证，未宣称全局跨设备ABA栅栏。
- 同一user://并行多个活进程写同journal、删除应用数据/卸载不在本轮保证范围；本轮验证的是旧进程已死后再重启。坏档/孤立tmp会冻结，需维护处理，不自动清档。
- 修复版仍需负责人独立正常server.ts/自然账号复查后决定GO；本执行不做发布决定。
