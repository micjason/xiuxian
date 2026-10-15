class_name UiSafeArea
extends RefCounted
## 刘海、挖孔、手势条的安全区。返回值单位是 1080×1920 画布像素，顺序 (左, 上, 右, 下)。
## 桌面或不支持的平台返回全 0。单个方向最多取 MAX_INSET，防止异常数据把界面挤没。

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


## 读取当前设备的安全区。viewport 用来换算画布与窗口像素的比例。
static func current(viewport: Viewport) -> Vector4:
	var window_width := float(DisplayServer.window_get_size().x)
	if window_width <= 0.0:
		return Vector4.ZERO
	var canvas_per_pixel := viewport.get_visible_rect().size.x / window_width
	return compute(DisplayServer.get_display_safe_area(), DisplayServer.screen_get_size(), canvas_per_pixel)
