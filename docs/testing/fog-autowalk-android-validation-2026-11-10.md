# Android pending可靠写盘与HUD修复（2026-11-10，北京时间 UTC+8）

## 结论与范围

原toybox方案在最低支持Android24确实不可用，不再以“失败即停走”作为该平台正常支持。现在只替换Android同步分支：Godot4.7.2内置JavaClassWrapper调用公开API21 `android.system.Os.open(path, O_RDONLY=0, 0) → fsync(fd) → close(fd)`；逐次检查异常，并在close前保存fsync异常结果。文件同步、原子rename、目录及其父目录同步、校验与账号/地图绑定逻辑保持。没有新增插件/AAR/Gradle依赖，没有改正式minSdk、targetSdk、版本或发布配置。

真实平台：盒子官方AOSP Android24 x86_64软件模拟器，SELinux Enforcing，实际安装Godot本地验证样包，普通应用UID10062（不是adb shell UID）。这不是ARM/真机实拍，也不是正式产品APK验收。

## 证据目录与红绿

以下路径相对 `/workspace/.deploy/fog-autowalk/android-validation/`；保留所有失败尝试与原日志。

| 项目 | 实际结果 / 证据 |
|---|---|
| 原实现实红 | `original-toybox-red-app-extract.txt`、`all-app-api24.log:48–51`：实际应用UID10062，file=false，directory_and_parent=false，STORAGE_UNAVAILABLE。Android24 shell还返回toybox unknown command/127，但shell证据不冒充应用证据。 |
| 新原生同步实绿 | 同一普通应用UID10062，`all-app-api24.log:68–115`：file=true、directory_and_parent=true。生产journal `_write` 对无尾斜杠目录执行父目录同步；不是仅调用FileAccess.flush。 |
| 正常移动 | `normal-runtime-evidence.json`：真实FogMapPage/ApiClient/本地HTTP，8次committed，200→192，(3,10)→(6,5)，pending=false。此轮渲染开启。 |
| 进程重启、迟到POST | `android-runtime-evidence-v2.json` delayed：真实HTTP preHandler barrier挂住旧POST，应用UID内SIGKILL PID3120，重启PID3178读取磁盘pending；先reconcile取消，再放旧POST并用原body重放，均cancelled，200点、原位(3,10)、唯一账本1行，未新派move。 |
| 已落步丢响应、无网重启、恢复 | `android-runtime-evidence-v4.json`、`runtime-cases-v4.log`：应用PID2609真实落一步199/(3,9)，运输边界故意丢成功响应后SIGKILL；关闭自己的18085监听，重启PID2668从磁盘恢复且冻结；恢复自己的API后再启PID2723，reconcile读committed，仍199/(3,9)，唯一账本1行，持久化权威终态后清pending，0新move、1reconcile。日志分别为v4-committed-loss-app.log、v4-offline-recovery-app.log、v4-online-recovery-app.log。这是故障注入丢应答+真实关闭监听，不是实机无线断网。 |
| JNI测试 | 有效红 `jni-red-assertions.log`（4项均失败）；绿 `jni-green.log` 4/4、13断言。更早 `jni-red.log` 是类型推断解析错误，不算有效功能红。覆盖open失败、fsync异常不被close擦除、close失败、成功顺序。 |
| HUD测试 | `hud-red.log` 旧位置/旧余额与缺少已落地提示；`hud-green.log` 1/1、9断言。终态持久化失败仍冻结pending，不继续派步；只在终态校验成功时展示权威位置/余额，并提示“上一步已落地，记录保存失败，不能继续”。 |
| 修后针对性GUT | `gut-native-final.log` 53/53、215断言、exit0；仍有8孤儿及退出资源泄漏警告，不称无engine ERROR。 |

## 实跑命令与隔离

针对性命令（当时已执行，非建议现在重跑）：
```sh
HOME=/workspace/.deploy/fog-autowalk/android-validation/gut-home \
XIUXIAN_UI_MOCK=1 XIUXIAN_UPDATE_CHECK=0 \
/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64 --headless --path game \
-s addons/gut/gut_cmdln.gd \
-gtest=res://tests/unit/test_fog_autowalk.gd \
-gtest=res://tests/unit/test_fog_android_sync.gd \
-gtest=res://tests/unit/test_fog_route.gd \
-gtest=res://tests/unit/test_cave_fog_entry.gd -gexit
```

Android运行驱动：`python3 /workspace/.deploy/fog-autowalk/android-validation/run-android-cases-v2.py`（迟到取消成功，下一情景启动失败）及 `python3 /workspace/.deploy/fog-autowalk/android-validation/run-android-cases-v4.py`（只继续已commit/断网，exit0、ANDROID_RUNTIME_ALL_PASS）。完整命令、闩锁/kill/恢复逻辑在文件中；v4汇总的delayed字段明确引用v2原运行，不伪称v4重跑了取消。每个DB情景先保存并断言current_database()/inet_server_port()为 `xiuxian_fog_android_test|55439`，再访问自己的fixture API18085；不运行npm test，不连接5432，不碰负责人18084/其库/其旁注。此为fixture场景，不冒称自然注册完整生产链路。后端本轮无改动，未重跑全量517；历史7cde的私有517与独立验收保持原口径。

## 必须披露的限制

- KVM可建VM但CREATE_VCPU实际SIGSEGV139，故使用官方软件模拟器。Android35软件启动遇framework watchdog循环，未完成该平台应用验证；不是35已通过。
- Android24旧SwiftShader超过uniform上限。正常8步曾在渲染开启下完成，但第一轮重启驱动被GPU卡住超时，`runtime-cases.log` 原样保留，不算通过。v2迟到取消已通过，但下一阶段PID3244在进入业务脚本前死亡（同期lowmemorykiller报错，不能仅凭此确定死因），`api24-system-after-v2.log`与失败`runtime-cases-v2.log`保留。增加到2048MB后v3常规入口仍未进入业务脚本即超时，原日志保留，未把扩RAM当成修复。已核对官方模板GodotActivity启动参数处理；v4由应用自身UID用am启动自己的非导出GodotApp activity并传`--esa command_line_params --headless`，实际OS仍Android、UID10062，跳过虚拟GPU后实跑通过。没有改Godot模板、权限或产品。v2/v3/v4仅本地样包入口设置 `RenderingServer.render_loop_enabled=false`；同样实际Android进程、应用UID、生产page/store/JNI/HTTP，但**重启/断网证据是无渲染状态机验证，不是Android UI截图/触摸验收**。样包还设置max_renderable_lights=16（单独尝试无效），产品project.godot与资源完全未改。
- 样包使用官方4.7.2预编译debug模板、min24、target36、x86_64；正式产品target35未变。非Gradle模板改target35被正确拒绝的日志保留。没有把样包等同正式产品包。
- 已验证常规SIGKILL进程重建；没有硬件断电实验，FileAccess.flush不是物理持久化保证。实际调用并检查文件/目录fsync仍不能超越存储硬件谎报成功、磁盘损毁等故障。
- 历史共享测试库事故影响仍未知，最新私有结果不能抵消该事故。事故文档3a843b04及原日志保持，见 `fog-autowalk-test-db-incident-2026-11-09.md`。历史20条与513不是隔离证明。

## 上线边界

仅本地提交，未push/部署/改版本/正式APK或发布。保持先后台（兼容旧69 move、启用新协议/终态对账）后新包；新前端遇旧后端明确停止，不能降级。正式Android包/设备验收与发布由负责人负责，不由本地样包替代。

## 复核入口

- 普通应用正常8步：`normal-runtime-evidence.json` + 原渲染开启应用日志。
- 迟到POST取消实证：`android-runtime-evidence-v2.json` + `cancel-recovery-app.log`，并保留v2后续失败事实。
- 已commit/SIGKILL/真实无API监听/恢复：`android-runtime-evidence-v4.json` + 三份v4应用日志；v4的headless和旧delayed来源字段不可省略。
- 每轮身份：`v2-*-preflight.txt` / `v4-*-preflight.txt`，均预先保存55439/xiuxian_fog_android_test；复跑同样先核验，不用npm test。
- 本轮完成时间约 **01:10 北京时间 UTC+8**，比01:00平台阶段目标晚约10分钟；不改写原日志时间。
- 官方契约：<https://docs.godotengine.org/en/stable/classes/class_javaclasswrapper.html>；<https://developer.android.com/reference/android/system/Os>；<https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html>。源码/文档支持不是运行证据；运行证据单独列在上面。

## 最终提交前复跑与导入前提（01:14 北京时间 UTC+8）

`gut-native-precommit-final.log`：还原生成import元数据后直接运行复现52/53，唯一失败是入口测试加载icon_lingmu/icon_kuilei两张缺失ctex的engine错误，不是导航断言。没有修改或屏蔽该测试/资源。执行标准 `Godot --headless --editor --path game --import`（同上HOME与环境，`precommit-standard-import.log`）后，原四组完整命令复跑：`gut-native-precommit-imported.log` **53/53、215断言、exit0**，仍8孤儿及退出资源泄漏警告。先前失败日志保留。复核必须先标准导入；提交前仅还原本轮生成的tracked `.import`，不提交生成uid、依赖、owner旁注，不伪称干净cache免导入可跑。
