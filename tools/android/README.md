# Android 调试包（debug-signed APK）

目标：导出一个用调试密钥签名、能直接装到手机上的 APK，服务器地址**不写死**。

## 一次性准备

```bash
GODOT_VERSION=4.7.2 TOOLCHAIN=~/android-toolchain tools/android/setup_toolchain.sh
```

装 JDK 17、Android SDK（platform 35、build-tools）、Godot 4.7.2 导出模板、调试签名密钥，全部放在 `$TOOLCHAIN`，不碰系统。可重复运行。
调试密钥（`debug.keystore`）不进仓库（`.gitignore` 已排除 `*.keystore`、`*.apk`）。

## 导出

```bash
TOOLCHAIN=~/android-toolchain GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 \
  tools/android/build_debug_apk.sh --api-base http://192.168.1.20:8080 --out builds/xiuxian-debug.apk
```

- 脚本在临时目录里拷一份 `game/` 再导出，仓库里不会留下 `android/build`，也不会改工程设置。
- 默认只打 `arm64-v8a`（现在的手机都是）。`gradle_build` 方式导出，`minSdk 24`、`targetSdk 35`。
- 构建时给 `AndroidManifest.xml` 加了 `usesCleartextTraffic="true"`，因为局域网里的开发服务器是 `http://`。**正式包要换成 https 并去掉这一项。**
- 包名 `com.micjason.xiuxian`，版本在 `game/export_presets.cfg`（`version/code`、`version/name`），每次给别人装新包前把 `version/code` 加 1，否则手机会拒绝覆盖安装。

## 服务器地址怎么配

优先级从高到低（代码：`game/scripts/core/server_address.gd`）：

1. 命令行 `--api-base=http://host:port`（桌面调试）
2. 环境变量 `XIUXIAN_API_BASE`（桌面调试）
3. 登录页「服务器地址」输入框里保存的地址（存在 `user://server_url.txt`；**手机上主要用这个**）
4. 工程设置 `xiuxian/network/api_base_url`（`--api-base` 打包参数就是改写它；不填默认 `http://10.0.2.2:8080`，那是 Android **模拟器**访问电脑本机的地址）

真机连电脑上的后端：电脑和手机在同一个 Wi-Fi，后端监听 `0.0.0.0`（不是 `127.0.0.1`），手机上在登录页填 `http://电脑局域网IP:端口`。电脑防火墙要放行这个端口。

## 已验证 / 未验证

已验证（在 Linux 开发机上，Godot 4.7.2 headless 导出）：

- 导出成功，无报错；产物约 94 MB（其中 `libgodot_android.so` 约 76 MB，是引擎本身）。
- `aapt2 dump badging`：包名 `com.micjason.xiuxian`，`minSdk 24`，`targetSdk 35`，权限 `INTERNET`、`ACCESS_NETWORK_STATE`（还有导出模板自带的 `REQUEST_INSTALL_PACKAGES`，给"客户端更新"用）。
- `aapt2 dump xmltree`：`usesCleartextTraffic=true`。
- `apksigner verify --print-certs`：Verifies；APK Signature Scheme v2 通过；签名者 `CN=Android Debug`。
- 包内 `project.binary` 里能搜到 `xiuxian/network/api_base_url` 和构建时传入的地址，说明默认地址确实被改写。
- 包里只有 `lib/arm64-v8a`。
- 服务器地址解析、规范化、优先级有 GUT 单元测试（`game/tests/unit`）。

**未在真机验证**（本机没有手机，也没有 `/dev/kvm`，没法跑 Android 模拟器）：

- 安装、启动、触屏手感、刘海 / 挖孔 / 底部手势条的安全区、各分辨率下的布局。
- 手机上通过局域网连后端、`http` 明文请求是否被厂商 ROM 拦截。
- 字体在 Android 上的实际渲染（桌面 headless 里字体缓存会报错，已在测试里按"已知字体噪音"处理）。
- 运行性能、内存、耗电；`REQUEST_INSTALL_PACKAGES` 的应用内更新流程。
- 这个 APK 没有做 release 签名，也没有上架，只适合内部试玩。
