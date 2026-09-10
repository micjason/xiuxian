#!/bin/sh
# Shared by on-device 0.1.4 verifiers. Does not rebuild or publish.

ADB="${ADB:-/Volumes/kaixia/GodotDev/xiuxian/android/sdk/platform-tools/adb}"
PKG="${PKG:-com.micjason.xiuxian}"

require_adb_device() {
	if ! "$ADB" devices | /usr/bin/awk 'NR>1 && $2=="device" {found=1} END {exit found?0:1}'; then
		echo "No authorized Android device on this project's adb." >&2
		"$ADB" devices -l
		return 1
	fi
	return 0
}

keep_screen_on() {
	"$ADB" shell svc power stayon usb >/dev/null 2>&1 || true
}

restore_screen_timeout() {
	"$ADB" shell svc power stayon false >/dev/null 2>&1 || true
}

wake_device() {
	"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
	"$ADB" shell input keyevent KEYCODE_MENU >/dev/null 2>&1 || true
	# Only swipe a lock screen, and stay on the left edge so the gesture
	# cannot click the centered 突破境界 button.
	if is_keyguard_showing; then
		"$ADB" shell input swipe 80 2000 80 700 220 >/dev/null 2>&1 || true
	fi
}

is_screen_awake() {
	"$ADB" shell dumpsys power 2>/dev/null | /usr/bin/tr -d '\r' | /usr/bin/grep -Eq 'mWakefulness=Awake'
}

is_keyguard_showing() {
	dump=$("$ADB" shell dumpsys window 2>/dev/null | /usr/bin/tr -d '\r')
	printf '%s\n' "$dump" | /usr/bin/grep -Eq 'mDreamingLockscreen=true|isStatusBarKeyguard=true'
}

require_unlocked_screen() {
	wake_device
	keep_screen_on
	if ! is_screen_awake || is_keyguard_showing; then
		echo "Phone is locked or asleep; unlock it to finish 0.1.4 screenshots." >&2
		return 2
	fi
	return 0
}

# ColorOS/Android 14+ blocks shell from starting the unexported GodotApp
# component. Use the same MAIN/LAUNCHER path as the home-screen icon.
launch_game() {
	wake_device
	keep_screen_on
	if "$ADB" shell am start \
		-a android.intent.action.MAIN \
		-c android.intent.category.LAUNCHER \
		-p "$PKG" >/dev/null 2>&1; then
		return 0
	fi
	"$ADB" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

# Print "x y" for the wide gold action bar (突破境界 / 收下), not the
# small realm seal. Phone screenshots are 1440x3168; 1080x1920 mapping
# lands a few dozen pixels below this button.
gold_button_center() {
	path="$1"
	/usr/bin/python3 - "$path" <<'PY'
from PIL import Image
import sys

im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size


def is_gold(p):
    r, g, b = p
    return r > 180 and g > 140 and b < 140 and r > b + 50 and g > b + 30


rows = []
for y in range(h):
    run = 0
    best = 0
    xs = []
    for x in range(0, w, 2):
        if is_gold(im.getpixel((x, y))):
            run += 2
            xs.append(x)
            if run > best:
                best = run
        else:
            run = 0
    if best >= 400 and xs:
        rows.append((y, min(xs), max(xs)))
if not rows:
    raise SystemExit("no gold action button")
clusters = []
cur = [rows[0]]
for row in rows[1:]:
    if row[0] <= cur[-1][0] + 3:
        cur.append(row)
    else:
        clusters.append(cur)
        cur = [row]
clusters.append(cur)
# Prefer the tall wide bar (button), not the thin realm-seal ring.
best = max(clusters, key=lambda c: (c[-1][0] - c[0][0], c[-1][0]))
y0, y1 = best[0][0], best[-1][0]
x0 = min(r[1] for r in best)
x1 = max(r[2] for r in best)
print("%d %d" % ((x0 + x1) // 2, (y0 + y1) // 2))
PY
}

tap_gold_button() {
	path="$1"
	point=$(gold_button_center "$path")
	echo "tap gold $path -> $point"
	"$ADB" shell input tap $point
}

GAME_WINDOW_RECT_CACHE=""

# Print "x y w h" for the running game window. Falls back to the full
# framebuffer so taps stay inside Godot's letterboxed 1080x1920 view.
game_window_rect() {
	if [ -n "$GAME_WINDOW_RECT_CACHE" ]; then
		printf '%s\n' "$GAME_WINDOW_RECT_CACHE"
		return 0
	fi
	GAME_WINDOW_RECT_CACHE=$(game_window_rect_uncached)
	printf '%s\n' "$GAME_WINDOW_RECT_CACHE"
}

game_window_rect_uncached() {
	/usr/bin/python3 - "$ADB" "$PKG" <<'PY'
import re, subprocess, sys

adb, pkg = sys.argv[1], sys.argv[2]


def wm_size():
    raw = subprocess.check_output([adb, "shell", "wm", "size"], text=True, errors="replace")
    match = re.search(r"(\d+)x(\d+)", raw)
    if not match:
        raise SystemExit("unable to read wm size")
    return 0, 0, int(match.group(1)), int(match.group(2))


def parse_frame(text):
    match = re.search(r"mFrame=\[(\d+),(\d+)\]\[(\d+),(\d+)\]", text)
    if match:
        left, top, right, bottom = (int(x) for x in match.groups())
        if right > left and bottom > top:
            return left, top, right - left, bottom - top
    match = re.search(r"mAppBounds=Rect\((\d+),\s*(\d+)\s*-\s*(\d+),\s*(\d+)\)", text)
    if match:
        left, top, right, bottom = (int(x) for x in match.groups())
        if right > left and bottom > top:
            return left, top, right - left, bottom - top
    return None


x, y, w, h = wm_size()
try:
    dump = subprocess.check_output(
        [adb, "shell", "dumpsys", "window"],
        text=True,
        errors="replace",
        timeout=20,
    )
except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
    dump = ""
needle = "com.godot.game.GodotApp"
idx = dump.find(needle)
if idx >= 0:
    parsed = parse_frame(dump[max(0, idx - 800) : idx + 4000])
    if parsed:
        x, y, w, h = parsed
print("%d %d %d %d" % (x, y, w, h))
PY
}

require_game_screenshot() {
	path="$1"
	/usr/bin/python3 - "$path" <<'PY'
import struct, sys, zlib

path = sys.argv[1]


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


data = open(path, "rb").read()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit(0)
pos = 8
width = height = bit = color_type = None
idat = b""
while pos + 8 <= len(data):
    length = struct.unpack(">I", data[pos : pos + 4])[0]
    kind = data[pos + 4 : pos + 8]
    chunk = data[pos + 8 : pos + 8 + length]
    pos += 12 + length
    if kind == b"IHDR":
        width, height, bit, color_type = struct.unpack(">IIBB", chunk[:10])
    elif kind == b"IDAT":
        idat += chunk
    elif kind == b"IEND":
        break
if width is None or bit != 8 or color_type not in (2, 6):
    sys.exit(0)
if width < 200 or height < 200:
    print("screenshot is too small to be the game", file=sys.stderr)
    sys.exit(2)
raw = zlib.decompress(idat)
bpp = 3 if color_type == 2 else 4
stride = width * bpp
prev = bytearray(stride)
index = 0
total = 0.0
count = 0
step_x = max(1, width // 18)
step_y = max(1, height // 32)
for y in range(height):
    filt = raw[index]
    index += 1
    row = bytearray(raw[index : index + stride])
    index += stride
    if filt == 1:
        for x in range(stride):
            row[x] = (row[x] + (row[x - bpp] if x >= bpp else 0)) & 255
    elif filt == 2:
        for x in range(stride):
            row[x] = (row[x] + prev[x]) & 255
    elif filt == 3:
        for x in range(stride):
            left = row[x - bpp] if x >= bpp else 0
            row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
    elif filt == 4:
        for x in range(stride):
            left = row[x - bpp] if x >= bpp else 0
            up_left = prev[x - bpp] if x >= bpp else 0
            row[x] = (row[x] + paeth(left, prev[x], up_left)) & 255
    elif filt != 0:
        sys.exit(0)
    if y % step_y == 0:
        for x in range(0, width, step_x):
            off = x * bpp
            r, g, b = row[off], row[off + 1], row[off + 2]
            total += (r * 0.299 + g * 0.587 + b * 0.114) / 255.0
            count += 1
    prev = row
if count == 0:
    sys.exit(0)
luma = total / count
# The 0.1.4 ink UI stays dark. A bright lock-screen photo is not the game.
if luma > 0.55:
    print("screenshot looks like a lock screen (luma=%.2f)" % luma, file=sys.stderr)
    sys.exit(2)
print("screenshot luma=%.2f" % luma)
PY
}

OCR_SWIFT="${OCR_SWIFT:-/Volumes/kaixia/projects/xiuxian/tools/release/ocr_screenshot.swift}"

ocr_crop_args() {
	path="$1"
	/usr/bin/python3 - "$path" "$(game_window_rect)" "$("$ADB" shell wm size | /usr/bin/tr -d '\r')" <<'PY'
import re, struct, sys

path, rect, wm = sys.argv[1], sys.argv[2], sys.argv[3]
parts = [int(v) for v in rect.split()]
if len(parts) != 4:
    raise SystemExit(0)
x, y, w, h = parts
data = open(path, "rb").read(24)
if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit(0)
pw, ph = struct.unpack(">II", data[16:24])
match = re.search(r"(\d+)x(\d+)", wm)
if not match or pw < 8 or ph < 8:
    print("%d %d %d %d" % (x, y, w, h))
    raise SystemExit(0)
dw, dh = int(match.group(1)), int(match.group(2))
sx = pw / float(dw)
sy = ph / float(dh)
cx = max(0, int(round(x * sx)))
cy = max(0, int(round(y * sy)))
cw = min(pw - cx, int(round(w * sx)))
ch = min(ph - cy, int(round(h * sy)))
if cw > 8 and ch > 8:
    print("%d %d %d %d" % (cx, cy, cw, ch))
PY
}

ocr_screenshot() {
	path="$1"
	out="${path%.png}.ocr.txt"
	crop=$(ocr_crop_args "$path" || true)
	if [ -n "$crop" ]; then
		# shellcheck disable=SC2086
		/usr/bin/swift "$OCR_SWIFT" "$path" $crop > "$out"
	else
		/usr/bin/swift "$OCR_SWIFT" "$path" > "$out"
	fi
	echo "$out"
}

ocr_has() {
	txt="$1"
	needle="$2"
	/usr/bin/python3 - "$txt" "$needle" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
needle = sys.argv[2]
if needle in text:
    raise SystemExit(0)
compact = "".join(text.split()).replace("\u3000", "")
want = "".join(needle.split()).replace("\u3000", "")
raise SystemExit(0 if want and want in compact else 1)
PY
}

require_ocr_any() {
	path="$1"
	shift
	txt="${path%.png}.ocr.txt"
	ocr_screenshot "$path" >/dev/null
	echo "ocr=$txt"
	for needle in "$@"; do
		if ocr_has "$txt" "$needle"; then
			echo "ocr contains $needle"
			return 0
		fi
	done
	echo "screenshot $path OCR missing any of ($*)" >&2
	/usr/bin/head -24 "$txt" >&2
	return 1
}

require_ocr_all() {
	path="$1"
	shift
	txt="${path%.png}.ocr.txt"
	ocr_screenshot "$path" >/dev/null
	echo "ocr=$txt"
	missing=""
	for needle in "$@"; do
		if ocr_has "$txt" "$needle"; then
			echo "ocr contains $needle"
		else
			missing="$missing $needle"
		fi
	done
	if [ -n "$missing" ]; then
		echo "screenshot $path OCR missing$missing" >&2
		/usr/bin/head -24 "$txt" >&2
		return 1
	fi
	return 0
}
