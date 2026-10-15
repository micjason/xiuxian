class_name ServerAddress
extends RefCounted
## 服务器地址：打包后的 APK 不写死 localhost，运行时按下面的优先级决定（高 → 低）：
## 1. 命令行参数 --api-base=http://host:port（桌面调试用）
## 2. 环境变量 XIUXIAN_API_BASE（桌面调试用）
## 3. 玩家在登录页「服务器地址」里保存的地址（user://server_url.txt，手机上主要用这个）
## 4. 工程设置 xiuxian/network/api_base_url（打包脚本可在构建时改写它，见 tools/android/README.md）
## 只接受 http / https。没写协议时补 http://，去掉结尾的 /。

const SETTING := "xiuxian/network/api_base_url"
const FALLBACK := "http://127.0.0.1:8080"
const SAVED_PATH := "user://server_url.txt"
const ENV_NAME := "XIUXIAN_API_BASE"
const ARG_PREFIX := "--api-base="


## 把玩家输入整理成地址；不合法返回空字符串。
static func normalize(text: String) -> String:
	var value := text.strip_edges()
	if value.is_empty():
		return ""
	if not value.contains("://"):
		value = "http://" + value
	var lower := value.to_lower()
	if not (lower.begins_with("http://") or lower.begins_with("https://")):
		return ""
	var rest := value.substr(value.find("://") + 3).trim_suffix("/")
	if rest.is_empty() or rest.begins_with(":") or rest.contains(" "):
		return ""
	return value.substr(0, value.find("://") + 3) + rest


## 纯函数：按优先级挑地址（测试用）。args 是命令行用户参数。
static func resolve(args: PackedStringArray, env_value: String, saved: String, setting: String) -> String:
	for arg in args:
		if arg.begins_with(ARG_PREFIX):
			var from_arg := normalize(arg.substr(ARG_PREFIX.length()))
			if not from_arg.is_empty():
				return from_arg
	var from_env := normalize(env_value)
	if not from_env.is_empty():
		return from_env
	var from_saved := normalize(saved)
	if not from_saved.is_empty():
		return from_saved
	var from_setting := normalize(setting)
	return from_setting if not from_setting.is_empty() else FALLBACK


static func saved() -> String:
	if not FileAccess.file_exists(SAVED_PATH):
		return ""
	return FileAccess.get_file_as_string(SAVED_PATH).strip_edges()


## 玩家保存地址。返回规范化后的地址；输入不合法返回空字符串（不保存）。
static func save(text: String) -> String:
	var value := normalize(text)
	if value.is_empty():
		return ""
	var file := FileAccess.open(SAVED_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
	return value


static func clear_saved() -> void:
	if FileAccess.file_exists(SAVED_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED_PATH))


static func current() -> String:
	return resolve(OS.get_cmdline_user_args(), OS.get_environment(ENV_NAME), saved(), str(ProjectSettings.get_setting(SETTING, FALLBACK)))
