class_name UpdateManifest
extends RefCounted
## 更新信息：服务器 <地址>/download/latest.json（tools/deploy/release_apk.sh 生成）：
##   {"versionCode": 31, "versionName": "0.11.0", "url": "http://101.132.74.32:8090/download/xiuxian-dev2-0.11.0-31.apk",
##    "sha256": "<64 位十六进制>", "size": 93000000, "notes": "更新说明", "force": false}
## url 可以是相对路径（/download/…），按服务器地址补全。
## 只接受：https，或者和服务器地址同一个主机的 http（现在只有 IP + http）。
## 安全说明：http 下 latest.json 可能被中间人改，但 Android 只会用同一个签名的包覆盖安装，改过的包装不上；下载后还会校验 sha256 和大小。
## 也兼容旧格式（version / version_code / apk_url / apk_sha256 / apk_size / release_notes / minimum_version）。

var version: String
var version_code: int
var minimum_version: String
var apk_url: String
var apk_size: int
var apk_sha256: String
var release_notes: String
var force_update := false


static func from_json(text: String, server_base: String = "") -> UpdateManifest:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parsed
	var manifest := UpdateManifest.new()
	manifest.version = str(data.get("versionName", data.get("version", ""))).strip_edges()
	manifest.version_code = int(data.get("versionCode", data.get("version_code", 0)))
	manifest.minimum_version = str(data.get("minimum_version", "0.1.0")).strip_edges()
	manifest.apk_url = resolve_url(str(data.get("url", data.get("apk_url", ""))).strip_edges(), server_base)
	manifest.apk_size = int(data.get("size", data.get("apk_size", 0)))
	manifest.apk_sha256 = str(data.get("sha256", data.get("apk_sha256", ""))).to_lower().strip_edges()
	manifest.release_notes = str(data.get("notes", data.get("release_notes", ""))).strip_edges()
	manifest.force_update = bool(data.get("force", data.get("force_update", false)))
	if not manifest.is_valid(server_base):
		return null
	return manifest


## 相对路径按服务器地址补全。指向 /download/ 的 http 地址一律从“当前连接的服务器”下载
## （同一台服务器换了访问方式时也能用，例如调试时走 SSH 隧道 127.0.0.1）。其余完整地址不变。
static func resolve_url(url: String, server_base: String) -> String:
	if server_base.is_empty():
		return url
	var base := server_base.trim_suffix("/")
	if url.begins_with("/"):
		return base + url
	if url.begins_with("http://") and _host_of(url) != _host_of(base):
		var rest := url.substr(7)
		var path := rest.substr(rest.find("/")) if rest.contains("/") else ""
		if path.begins_with("/download/"):
			return base + path
	return url


static func _host_of(url: String) -> String:
	var rest := url.substr(url.find("://") + 3) if url.contains("://") else url
	var slash := rest.find("/")
	return (rest if slash < 0 else rest.substr(0, slash)).to_lower()


func is_valid(server_base: String = "") -> bool:
	return (
		AppVersion.is_valid(version)
		and version_code > 0
		and AppVersion.is_valid(minimum_version)
		and url_allowed(apk_url, server_base)
		and apk_sha256.length() == 64
		and apk_sha256.is_valid_hex_number(false)
	)


static func url_allowed(url: String, server_base: String) -> bool:
	if url.begins_with("https://"):
		return true
	if url.begins_with("http://127.0.0.1") or url.begins_with("http://localhost"):
		return true
	return url.begins_with("http://") and not server_base.is_empty() and _host_of(url) == _host_of(server_base)


func as_dictionary() -> Dictionary:
	return {
		"version": version,
		"version_code": version_code,
		"minimum_version": minimum_version,
		"apk_url": apk_url,
		"apk_size": apk_size,
		"apk_sha256": apk_sha256,
		"release_notes": release_notes,
		"force_update": force_update or (minimum_version == version and version != "0.1.0"),
	}
