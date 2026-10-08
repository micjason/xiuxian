extends Node

func api_base_url() -> String:
	return str(ProjectSettings.get_setting("xiuxian/network/api_base_url", "http://127.0.0.1:8080")).trim_suffix("/")
