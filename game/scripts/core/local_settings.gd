class_name LocalSettings
extends RefCounted
## 本机设置（只存在这台设备上，不随账号走）：音乐 / 音效开关。
## 存在 user://settings.cfg；改了立刻写盘并作用到音频总线（Music / SFX，没有就在运行时建出来，
## 以后加的背景音乐、音效播放器把 bus 设成这两个就自动受开关控制）。

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "audio"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

## 测试可改成临时路径。
static var path := DEFAULT_PATH


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path):
		cfg.load(path)
	return cfg


static func music_on() -> bool:
	return bool(_load().get_value(SECTION, "music", true))


static func sfx_on() -> bool:
	return bool(_load().get_value(SECTION, "sfx", true))


static func set_music_on(value: bool) -> void:
	_save("music", value)
	apply_audio()


static func set_sfx_on(value: bool) -> void:
	_save("sfx", value)
	apply_audio()


static func _save(key: String, value: Variant) -> void:
	var cfg := _load()
	cfg.set_value(SECTION, key, value)
	cfg.save(path)


## 确保 Music / SFX 总线存在（都接到 Master），按开关静音。启动时和每次切换时调用。
static func apply_audio() -> void:
	_bus(BUS_MUSIC)
	_bus(BUS_SFX)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MUSIC), not music_on())
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_SFX), not sfx_on())


static func _bus(bus_name: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	return index
