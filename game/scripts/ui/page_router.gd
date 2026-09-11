class_name PageRouter
extends RefCounted

var current_page: String = ""
var _pages: Dictionary = {}
var _tabs: Dictionary = {}


func register_page(page_id: String, page: Control, tab: Button = null) -> void:
	if page_id.is_empty() or page == null:
		return
	_pages[page_id] = page
	if tab != null:
		_tabs[page_id] = tab


func show_page(page_id: String) -> bool:
	if not _pages.has(page_id):
		return false
	current_page = page_id
	for id in _pages.keys():
		var page := _pages[id] as Control
		page.visible = str(id) == page_id
	for id in _tabs.keys():
		var tab := _tabs[id] as Button
		tab.set_meta("selected", str(id) == page_id)
	return true


func page(page_id: String) -> Control:
	return _pages.get(page_id, null)


func tab(page_id: String) -> Button:
	return _tabs.get(page_id, null)


func page_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id in _pages.keys():
		ids.append(str(id))
	return ids
