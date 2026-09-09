#!/bin/sh
set -eu

PUBKEY="${1:-/Volumes/kaixia/GodotDev/xiuxian/signing/update-public.pem}"
WORKDIR="${TMPDIR:-/tmp}/xiuxian-update-check"
mkdir -p "$WORKDIR"

check_ref() {
	ref="$1"
	base="$2"
	json="$WORKDIR/$ref.json"
	sig="$WORKDIR/$ref.sig"
	hdr="$WORKDIR/$ref.hdr"
	/usr/bin/curl -fsS -D "$hdr" -A "XiuxianUpdater/0.1" -H "Cache-Control: no-cache" "$base/update.json" -o "$json"
	/usr/bin/curl -fsS -A "XiuxianUpdater/0.1" -H "Cache-Control: no-cache" "$base/update.sig" -o "$sig"
	if ! /usr/bin/openssl dgst -sha256 -verify "$PUBKEY" -signature "$sig" "$json" >/dev/null; then
		echo "$ref signature=FAIL"
		return 1
	fi
	python3 - "$json" "$ref" "$hdr" <<'PY'
import json, sys, urllib.request
path, ref, header_path = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path))
url = data["apk_url"]
headers = {}
for line in open(header_path, encoding="utf-8", errors="replace"):
    if ":" not in line:
        continue
    key, value = line.split(":", 1)
    headers[key.strip().lower()] = value.strip()
req = urllib.request.Request(url, method="HEAD", headers={
    "User-Agent": "XiuxianUpdater/0.1",
    "Accept": "application/octet-stream",
})
try:
    with urllib.request.urlopen(req, timeout=30) as response:
        code = response.status
except urllib.error.HTTPError as error:
    code = error.code
extra = []
if headers.get("x-jsd-version"):
    extra.append(f"jsd={headers['x-jsd-version']}")
if headers.get("age"):
    extra.append(f"age={headers['age']}")
print(
    f"{ref} version={data['version']} sha={data['apk_sha256'][:16]} "
    f"asset={url.rsplit('/', 1)[-1]} apk_http={code} signature=OK"
    + ((" " + " ".join(extra)) if extra else "")
)
if code >= 400:
    sys.exit(2)
PY
}

failed=0
check_ref "jsdelivr-main" "https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@main" || failed=1
check_ref "jsdelivr-latest" "https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@latest" || failed=1
check_ref "github-main" "https://raw.githubusercontent.com/micjason/xiuxian-releases/main" || failed=1
python3 - "$WORKDIR" <<'PY'
import json, pathlib, sys
work = pathlib.Path(sys.argv[1])
try:
    main = json.loads((work / "jsdelivr-main.json").read_text())
    github = json.loads((work / "github-main.json").read_text())
except OSError:
    sys.exit(0)
if main.get("apk_sha256") == github.get("apk_sha256"):
    print("jsdelivr-main matches github-main")
else:
    print("jsdelivr-main STALE vs github-main")
PY
exit "$failed"
