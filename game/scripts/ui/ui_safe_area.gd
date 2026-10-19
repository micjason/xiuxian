class_name UiSafeArea
extends RefCounted
## 刘海、挖孔、手势条的安全区。返回值单位是画布像素（宽度 1080 的画布），顺序 (左, 上, 右, 下)。
## 只在手机（Android / iOS）上读系统安全区；桌面、编辑器里一律全 0。
## 原因（v10）：桌面上 DisplayServer.get_display_safe_area() 返回的是“整块屏幕里扣掉菜单栏 / Dock / 刘海”的区域，
## 以屏幕为基准，和游戏窗口没有关系；拿来当手机安全区，会在窗口底部多出一截空白、把标签栏顶到中间。
## 单个方向最多取 MAX_INSET，防止异常数据把界面挤没。

const MAX_INSET := 240.0


## 纯函数，便于单元测试：safe 是系统给的安全矩形（屏幕像素），screen 是屏幕像素尺寸，
## canvas_per_pixel 是 画布宽度 ÷ 窗口像素宽度。
static func compute(safe: Rect2i, screen: Vector2i, canvas_per_pixel: float) -> Vector4:
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var left := maxf(0.0, float(safe.position.x))
	var top := maxf(0.0, float(safe.position.y))
	var right := maxf(0.0, float(screen.x - (safe.position.x + safe.size.x)))
	var bottom := maxf(0.0, float(screen.y - (safe.position.y + safe.size.y)))
	var scaled := Vector4(left, top, right, bottom) * canvas_per_pixel
	return Vector4(
		minf(scaled.x, MAX_INSET),
		minf(scaled.y, MAX_INSET),
		minf(scaled.z, MAX_INSET),
		minf(scaled.w, MAX_INSET)
	)


## 开发用：环境变量 XIUXIAN_SAFE_AREA="左,上,右,下"（画布像素）可在桌面上模拟刘海/手势条做截图；
## 正式包里没有这个环境变量，不起作用。
static func debug_override() -> Variant:
	var raw := OS.get_environment("XIUXIAN_SAFE_AREA")
	if raw.is_empty():
		return null
	var parts := raw.split(",")
	if parts.size() != 4:
		return null
	return Vector4(
		clampf(float(parts[0]), 0.0, MAX_INSET), clampf(float(parts[1]), 0.0, MAX_INSET),
		clampf(float(parts[2]), 0.0, MAX_INSET), clampf(float(parts[3]), 0.0, MAX_INSET))


## 这个平台是否有“系统安全区”这回事（只有手机有；桌面和编辑器没有）。
static func platform_has_safe_area() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


## 纯函数：决定要不要用系统给的安全区（便于单元测试）。桌面一律 0，手机才换算。
static func resolve(mobile: bool, safe: Rect2i, screen: Vector2i, canvas_per_pixel: float) -> Vector4:
	if not mobile:
		return Vector4.ZERO
	return compute(safe, screen, canvas_per_pixel)


## 读取当前设备的安全区。viewport 用来换算画布与窗口像素的比例。
static func current(viewport: Viewport) -> Vector4:
	var forced: Variant = debug_override()
	if forced != null:
		return forced as Vector4
	if not platform_has_safe_area():
		return Vector4.ZERO
	var window_width := float(DisplayServer.window_get_size().x)
	if window_width <= 0.0:
		return Vector4.ZERO
	var canvas_per_pixel := viewport.get_visible_rect().size.x / window_width
	return resolve(true, DisplayServer.get_display_safe_area(), DisplayServer.screen_get_size(), canvas_per_pixel)
