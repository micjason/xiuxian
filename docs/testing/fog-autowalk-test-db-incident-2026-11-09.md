# 迷雾自动行走：共享测试库误清理事故（2026-11-09）

## 状态与责任

执行者误用了会覆盖连接地址的npm test，违反“不得清共享库”的约束。不是单纯文案错误，也不能因为测试通过就忽略。此前“未连接共享5432”“全部后端验证均私有隔离”的声明撤回。本文仅基于自己的原终端记录、现存日志、源码只读整理；本轮**没有连接任何数据库、跑测试、恢复库、删改原日志或联系他人**。未触碰负责人18084/数据库/旁注，未改功能或Android fsync。

证据索引：`/workspace/.deploy/fog-autowalk/incident/evidence-index.json`（路径、大小、SHA256、语句首现行号）；同目录`CORRECTIONS.md`、`original-command-and-timing.txt`、`sanitized-script-and-log-excerpts.txt`、`withDb-helper-readonly.txt`。原文件保留原位，敏感DSN用户信息不复制到报告。

## 实际命令与准确窗口

来源：自己的`/home/box/.cursor/projects/workspace/terminals/700379.txt`第3–14行，工作目录`/workspace/xiuxian-ui-fog-autowalk`。以下外层地址原本没有密码，命令真实摘录而非重构：

```sh
DATABASE_URL=postgres://box@127.0.0.1:55439/xiuxian_fog_autowalk_test npm test --prefix backend -- --maxWorkers=1 > /workspace/.deploy/fog-autowalk/backend-final-full.log 2>&1
```

- 起：**2026-11-09 23:21:33.459 北京时间 UTC+8**。
- 止：**2026-11-09 23:24:40.432 北京时间 UTC+8**。
- 耗时186973ms，进程exit0。这是命令进程窗口，不能据此精确到每条TRUNCATE的发生时间。
- 旧日志最终130文件513通过；这些是**共享测试库上的结果，不再作为隔离证明**。

## 外层DATABASE_URL为何没有生效

`--prefix backend`选择`backend/package.json`的`scripts.test`。该脚本自行使用shell行内变量赋值，等价于下述脱敏文本（不是建议执行的命令）：

```text
DATABASE_URL=postgres://<USERINFO_REDACTED>@127.0.0.1:5432/xiuxian_test vitest run
```

外层变量只先进入npm环境；npm启动脚本shell后，脚本中更近的`DATABASE_URL=...`覆盖它，Vitest继承的是5432地址。`-- --maxWorkers=1`只追加Vitest参数，不会撤销此赋值。`backend/src/test/db.ts:56–78`读取`process.env.DATABASE_URL`直接创建postgres连接，没有私有库/端口白名单；`withDb`是`withCleanDb`别名。package及helper与事故旧head e8513199相比没有变化。本轮未修改脚本或helper。

## 证据强度：直接记录与推断分开

| 内容 | 证据与边界 |
|---|---|
| 实际外层命令、工作目录、窗口、退出码 | 直接：700379终端元数据；标题写“private”是当时错误意图，不是连接证明。 |
| 实际启动的npm脚本指向5432/xiuxian_test | 直接：`backend-final-full.log:2–6`的npm脚本回显，及package脚本；userinfo已脱敏。 |
| 确实执行TRUNCATE且触发CASCADE | 直接：同日志PostgreSQL NOTICE的`where: SQL statement "TRUNCATE TABLE ... RESTART IDENTITY CASCADE"`与`truncate cascades to table ...`，不是仅从helper猜测。 |
| 本轮513连到共享127.0.0.1:5432/xiuxian_test | 强关联结论：脚本回显+helper读同一环境变量+真实Postgres NOTICE+运行成功。**事故运行没有保存current_database()/inet_server_port()查询结果，也没有服务端连接审计/session id。**不能声称当时做过服务端身份SELECT。 |
| 生产数据库没有被该命令指定 | 命令及脚本只指本机测试目标；没有审计其他运行或证明所有生产数据状态。不能把“非生产目标”扩大为“没有任何下游影响”。 |

## withDb实际清理范围与已列出表名

只读helper显示它**没有固定表名清单**，而是运行动态枚举：

```sql
DO $$ DECLARE r RECORD; BEGIN
  FOR r IN (
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename <> '__drizzle_migrations'
  ) LOOP
    EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' RESTART IDENTITY CASCADE';
  END LOOP;
END $$;
```

因此意图范围为当时public中除`__drizzle_migrations`之外全部普通表，重置关联identity序列并级联；函数在每次withDb用例前执行，不是每次都回滚的fixture事务。CASCADE还可能扩大影响。**不连接共享库，就不能事后列出当时完整真实目录、行数、序列和跨schema外键图。**下列只是现存日志直接可见下界，不能假称完整受影响表清单。

### 日志直接出现的TRUNCATE语句表名（4个）

- `content_releases`：原日志第14行。
- `content_drop_tables`：原日志第62行。
- `repair_previews`：原日志第75行。
- `players`：原日志第88行。

### 日志明确出现的CASCADE目标（23个）

- `items`：首现原日志第13行。
- `realms`：首现原日志第26行。
- `skills`：首现原日志第37行。
- `content_documents`：首现原日志第48行。
- `content_drop_entries`：首现原日志第61行。
- `repair_applications`：首现原日志第74行。
- `player_states`：首现原日志第87行。
- `notice_dismissals`：首现原日志第111行。
- `player_notices`：首现原日志第122行。
- `idempotency_keys`：首现原日志第133行。
- `player_items`：首现原日志第144行。
- `player_skills`：首现原日志第155行。
- `player_stage_progress`：首现原日志第166行。
- `player_offline_reports`：首现原日志第177行。
- `equipment_grants`：首现原日志第188行。
- `player_active_buffs`：首现原日志第199行。
- `enhance_exp_migrations`：首现原日志第210行。
- `player_dongfu_plots`：首现原日志第223行。
- `player_dongfu_alchemy`：首现原日志第234行。
- `player_dongfu`：首现原日志第245行。
- `player_dongfu_forge`：首现原日志第256行。
- `player_slot_enhances`：首现原日志第267行。
- `player_fog_runs`：首现原日志第278行。

## 已知与未知影响

已知：共享测试目标发生真实TRUNCATE/CASCADE，多次清空测试表并RESTART IDENTITY；日志至少直接列出上述4个语句目标与23个级联目标。513运行结束成功不代表没有破坏隔离。若当时表有数据，清理会删除；不能从NOTICE推断每张表当时非空或具体丢失数量。测试会再次插入fixture，结束后也不一定是空库。

未知：其他人/其他并行测试是否正在使用、其数据是否丢失或被fixture替代、断言/锁等待/序列是否受影响、最终数据状态、是否需要修复。**不可断言其他测试未受影响。**没有连接共享5432取证、查询活动进程、恢复库或擅自通知他人；是否开展后续调查由负责人决定。

## 历史结果与隔离声明更正

- 原20条矩阵/`counterexamples-20.json`所依附的旧513后端跑批是在共享库；该历史整组结果**不能作为隔离验收证明**。其中纯GUT/PC截图不访问PostgreSQL，不能反过来杜撰“每条都独立执行过SQL”。当前handoff显式区分旧口径与新517复跑。
- 原`verification-summary.json`、旧`result-e8513199-before-restart-correction.txt`、旧设计文件保留不改，旁置`incident/CORRECTIONS.md`明确撤回全程隔离声明。它们不是当前安全执行证明。
- 更早512的700373元数据是direct vitest指向55439；**本次未找到该次预先SELECT库名/端口记录**。原512输出路径与513相同，已在事故命令的`>`重定向时被覆盖，不是本轮删除日志。只保留现存记录，不编造已不存在的512完整日志，不将当前513文件冒充512。
- 最新517的700402命令**确有预先查询**：tsc/eslint成功后执行psql `SELECT current_database(), inet_server_port();`，再direct vitest。现存`restart-backend-full-final-v3.log:1`为`xiuxian_fog_restart_test|55439`；元数据窗口为2026-11-10 **00:06:46.595–00:10:36.873 北京时间 UTC+8**，Vitest开始00:07:01。该首行是当次原有记录，本轮没有事后补查或写入原日志。
- 边界：此SELECT来自预先psql连接，不是Vitest pool内查询；二者命令地址一致、helper按该DSN建独立连接。不能称同一连接持续身份审计。原命令使用`;`而非身份断言gate；后续安全步骤必须更严格。

## 后续安全复跑步骤（仅文档，本轮不执行）

每轮先确认55439是自己的隔离实例、独立数据库为本轮专用，若其他执行者在用则先由负责人协调，不碰共享库、不杀进程。**严禁npm test（包括外层设DSN的npm test）。**每次使用新的证据目录，先验证并保存身份结果，不复用`>`覆盖旧日志。

```sh
# 以下仅复跑说明；先取得对应测试执行权限。本次文档整理未执行。
set -eu
cd /workspace/xiuxian-ui-fog-autowalk/backend
export PGHOST=127.0.0.1 PGPORT=55439 PGUSER=box PGDATABASE=xiuxian_fog_restart_test
export DATABASE_URL="postgres://$PGUSER@$PGHOST:$PGPORT/$PGDATABASE"
export FOG_RESTART_GODOT=/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64
# 不要set -x；带真实密码时用已批准的凭据机制，禁止打印DSN。
EVIDENCE=$(mktemp -d /workspace/.deploy/fog-autowalk/safe-db-run-XXXXXX)
PSQL=/workspace/pg16/root/usr/lib/postgresql/16/bin/psql
# 显式目标与Vitest同源；无用户全局psqlrc。连接失败或结果不符即退出，不跑测试。
"$PSQL" -X -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -v ON_ERROR_STOP=1 -Atc 'SELECT current_database(), inet_server_port();' > "$EVIDENCE/preflight.txt"
if [ "$(tr -d '\r\n' < "$EVIDENCE/preflight.txt")" != 'xiuxian_fog_restart_test|55439' ]; then
  printf 'Database identity mismatch; stopped before tests\n' >&2
  exit 1
fi
# 保存前置身份后，直接调用Vitest；每轮都必须重新执行上述preflight。
node_modules/.bin/vitest run --maxWorkers=1 > "$EVIDENCE/vitest.log" 2>&1
```

若换独立库名，必须同时修改PGDATABASE、DATABASE_URL与断言期望，且仍固定55439；测试执行者负责预检并发占用，不将“脚本可跑”当运行授权。后续应单独评估通用helper安全护栏，本轮不扩改。

## 两项修复的精确红绿证据（仅引用既有文件）

- 重启：红`/workspace/.deploy/fog-autowalk/restart-process-red.log:296–323`，实际杀进程后新进程未创建原stepId墓碑，期望1行实际0；另有节点红`restart-node-red.log`。绿`restart-backend-full-final-v3.log:4441–4449`含`actual killed Godot process...`与其余2项重启实测，16项fog/全量517通过；脱敏请求顺序与状态`restart-evidence/delayed/redacted-evidence.json`（cancelled/200，显式新目标一步199）、`restart-evidence/committed/redacted-evidence.json`（离线exit2冻结、恢复committed仍199）、`restart-evidence/accounts/redacted-evidence.json`（foreignTombstones0，回A200）。
- 跨日退款：红`/workspace/.deploy/fog-autowalk/midnight-red.log:293–318`，旧GET将travelDay倒回11/9；绿同一`restart-backend-full-final-v3.log:3329–3594`中的`does not refund a new-day move when a previous-day GET was proven waiting on the player lock`执行且整份fog套件第4441行16/16通过，源码`steps.test.ts:642–687`验证两次余额均199、日期11/10，锁等待经pg_blocking_pids确认。
- 绿版本功能SHA为`7cde4b5eda57edfba45a9c843808c7cf8ba74c95`；本文独立文档提交不改变上述代码/测试结果，最终仍待负责人正常server.ts独立复查。
