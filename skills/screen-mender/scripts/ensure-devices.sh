#!/usr/bin/env bash
# ensure-devices.sh — screen-mender plugin 自帶、generic 裝置自動準備
#
# 目的：讓 screen-mender 不再依賴「使用者事先手動開好模擬器」。run 起手呼叫本 script：
#   查自管 pool（test_phone_NN）→ 不足就自動建 → 開機等 ready → stdout 回報 serial/udid。
# 設計成一棵環境決策樹：能自動解決就解決，缺到不能動就印「缺什麼、怎麼補」後以非 0 退出。
# 必須 generic（跑在任何機器）：絕不寫死單機路徑，全部 live 探測。
#
# 用法：
#   ensure-devices.sh --platform <android|ios> --count <N> \
#       [--prefix test_phone_] [--device-android "Pixel 8"] [--device-ios "iPhone 16"]
#     → stdout: 每行一個 ready 的 serial(Android)/udid(iOS)，供 orchestrator 綁 lane。
#       stderr: 人類可讀 checklist。
#       exit 0 = 成功（ready 台數可能 < N，代表降級，由 orchestrator 依行數降 lanes）。
#       exit 1 = 硬缺/零台（附「怎麼補」）。  exit 2 = 用法錯。
#
#   ensure-devices.sh --teardown [--prefix test_phone_] [--platform <android|ios>]
#     → 關掉開機中的 <prefix>NN、保留 profile（不刪 AVD/simulator）。
#       只動自管 pool，天然不碰使用者其他裝置。
#
# 機型策略（依使用者定）：優先用指定機型（Pixel 8 / iPhone 16）；
#   指定機型在本機不可用 → 退而採「本機最新同類機型」（最新 pixel / 最新 iPhone）。
#   連模擬器執行環境或可建素材都沒有 → 硬缺，請使用者安裝。不自動下載 SDK 元件。
#
# 相容性：macOS 預設 bash 3.2（不用 declare -A / mapfile / ${v^^}）、BSD sed/awk/grep。

set -uo pipefail

PREFIX="test_phone_"
PLATFORM=""
COUNT=0
DEVICE_ANDROID="Pixel 8"
DEVICE_IOS="iPhone 16"
MODE="ensure"          # ensure | teardown
BOOT_TIMEOUT=300       # 等開機完成上限（秒）
PORT_LO=5554
PORT_HI=5680

# ---- 共通 helper（一切人類訊息走 stderr，stdout 只放 serial/udid）----
log()  { printf '%s\n' "$*" >&2; }
warn() { printf '⚠️  %s\n' "$*" >&2; }
die()  { printf '❌ %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() { sed -n '2,30p' "$0" >&2; exit 2; }

pad2() { printf '%02d' "$1"; }   # 1 -> 01

detect_platform() {
  # orchestrator 通常會傳 --platform；沒傳時從 cwd repo 偵測（與 SKILL Phase 0 同規則）
  local top; top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  if ls "$top"/gradlew "$top"/*.gradle* >/dev/null 2>&1; then echo android; return; fi
  if ls "$top"/*.xcodeproj "$top"/*.xcworkspace "$top"/Podfile >/dev/null 2>&1; then echo ios; return; fi
  echo ""
}

# ============================ Android ============================
A_SDK=""; ADB=""; EMULATOR=""; AVDMANAGER=""; AVD_HOME=""

android_resolve_tools() {
  # SDK 根：env 優先，再常見路徑
  local c
  for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -n "$c" ] && [ -d "$c" ] && { A_SDK="$c"; break; }
  done
  # adb / emulator：PATH 優先，再 SDK 內
  if have adb; then ADB="adb"; elif [ -x "$A_SDK/platform-tools/adb" ]; then ADB="$A_SDK/platform-tools/adb"; fi
  if have emulator; then EMULATOR="emulator"; elif [ -x "$A_SDK/emulator/emulator" ]; then EMULATOR="$A_SDK/emulator/emulator"; fi
  # avdmanager：PATH 優先，再 cmdline-tools/latest、任一版本、舊 tools/bin
  if have avdmanager; then AVDMANAGER="avdmanager"
  elif [ -x "$A_SDK/cmdline-tools/latest/bin/avdmanager" ]; then AVDMANAGER="$A_SDK/cmdline-tools/latest/bin/avdmanager"
  else
    for c in "$A_SDK"/cmdline-tools/*/bin/avdmanager "$A_SDK"/tools/bin/avdmanager; do
      [ -x "$c" ] && { AVDMANAGER="$c"; break; }
    done
  fi
  AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
}

android_list_avds() { "$EMULATOR" -list-avds 2>/dev/null; }

android_is_booted() {
  [ "$("$ADB" -s "$1" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]
}

android_serial_for_avd() {
  # 回傳某 AVD 名目前對應的 booted serial（找不到回非 0）
  local want="$1" s nm
  for s in $("$ADB" devices 2>/dev/null | awk '/emulator-.*device$/{print $1}'); do
    nm=$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')
    [ "$nm" = "$want" ] && { printf '%s' "$s"; return 0; }
  done
  return 1
}

A_ASSIGNED_PORTS=" "   # 本次已分配（剛啟動、尚未現身 adb devices）的 port
android_free_port() {
  local used p
  used=$("$ADB" devices 2>/dev/null | awk '/emulator-/{print $1}' | sed 's/emulator-//')
  for p in $(seq "$PORT_LO" 2 "$PORT_HI"); do
    case " $used " in *" $p "*) continue;; esac
    case "$A_ASSIGNED_PORTS" in *" $p "*) continue;; esac
    A_ASSIGNED_PORTS="$A_ASSIGNED_PORTS$p "
    printf '%s' "$p"; return 0
  done
  return 1
}

android_wait_boot() {
  local s="$1" t=0
  "$ADB" -s "$s" wait-for-device 2>/dev/null
  while [ "$t" -lt "$BOOT_TIMEOUT" ]; do
    android_is_booted "$s" && { "$ADB" -s "$s" shell input keyevent 82 >/dev/null 2>&1; return 0; }
    sleep 3; t=$((t+3))
  done
  return 1
}

android_device_id_for() {
  # 在 avdmanager 的 device 清單裡，依「機型顯示名」精確找 device id（如 "Pixel 8" -> pixel_8）
  local want="$1"
  "$AVDMANAGER" list device 2>/dev/null | awk -v want="$want" '
    /^[[:space:]]*id:/   { l=$0; sub(/.*"/,"",l); sub(/".*/,"",l); cur=l }
    /^[[:space:]]*Name:/ { n=$0; sub(/^[[:space:]]*Name:[[:space:]]*/,"",n);
                           if (n==want){print cur; exit} }'
}

android_latest_pixel_id() {
  # fallback：取最新 Pixel device id（名稱 "Pixel <n>"，n 最大）
  "$AVDMANAGER" list device 2>/dev/null | awk '
    /^[[:space:]]*id:/   { l=$0; sub(/.*"/,"",l); sub(/".*/,"",l); cur=l }
    /^[[:space:]]*Name:/ { n=$0; sub(/^[[:space:]]*Name:[[:space:]]*/,"",n);
                           if (n ~ /^Pixel [0-9]+$/){ v=n; sub(/Pixel /,"",v);
                             if (v+0>=best+0){best=v+0; id=cur} } }
    END { if (id!="") print id }'
}

android_latest_image() {
  # 掃已安裝 system-images，組 sdkmanager package id，取最新 api。無則回非 0。
  local base="$A_SDK/system-images" rel best
  [ -d "$base" ] || return 1
  rel=$(cd "$base" 2>/dev/null && for api in */; do api=${api%/}; [ -d "$api" ] || continue
          for tag in "$api"/*/; do tag=${tag%/}; [ -d "$tag" ] || continue
            for abi in "$tag"/*/; do abi=${abi%/}; [ -d "$abi" ] && echo "$abi"; done
          done; done)
  [ -n "$rel" ] || return 1
  best=$(printf '%s\n' "$rel" | sort -V | tail -1)        # 例 android-37.0/google_apis.../arm64-v8a
  printf 'system-images;%s' "$(printf '%s' "$best" | tr '/' ';')"
}

android_pick_clone_template() {
  # 無 avdmanager 時的 fallback：挑現有（非 pool）AVD 當複製模板，偏好最新 pixel = 本機最新機型
  local prefix="$1" name cfg dev bn best="" bestn=-1
  for name in $(android_list_avds); do
    case "$name" in "$prefix"*) continue;; esac
    cfg="$AVD_HOME/$name.avd/config.ini"; [ -f "$cfg" ] || continue
    dev=$(grep -E '^hw\.device\.name=' "$cfg" | head -1 | cut -d= -f2 | tr -d '\r')
    case "$dev" in pixel_*) bn=$(printf '%s' "$dev" | sed -E 's/[^0-9]//g'); [ -z "$bn" ] && bn=0;; *) bn=0;; esac
    if [ -z "$best" ] || [ "$bn" -gt "$bestn" ]; then bestn="$bn"; best="$name"; fi
  done
  [ -n "$best" ] && printf '%s' "$best"
}

android_clone_avd() {
  # 複製模板 AVD 成新名（沿用模板機型 + image）。不需 avdmanager。
  local tmpl="$1" name="$2"
  local sdir="$AVD_HOME/$tmpl.avd" sini="$AVD_HOME/$tmpl.ini"
  local ddir="$AVD_HOME/$name.avd" dini="$AVD_HOME/$name.ini"
  [ -d "$sdir" ] || return 1
  rm -rf "$ddir" "$dini" 2>/dev/null
  cp -R "$sdir" "$ddir" || return 1
  # 清執行期產物，讓新 AVD 乾淨冷開機（避免繼承模板的鎖/快照/使用者資料）
  rm -rf "$ddir"/snapshots "$ddir"/*.lock "$ddir"/cache.img* "$ddir"/userdata-qemu.img* \
         "$ddir"/hardware-qemu.ini "$ddir"/emulator-user.ini "$ddir"/*.qcow2 \
         "$ddir"/multiinstance.lock "$ddir"/tmpAdbCmd* 2>/dev/null
  # 改 AvdId / displayname（用 awk 重寫，跨 mac/Linux，不依賴 sed -i 的平台差異）
  awk -v name="$name" '
    /^AvdId=/ { print "AvdId=" name; next }
    /^avd\.ini\.displayname=/ { print "avd.ini.displayname=" name; next }
    { print }' "$ddir/config.ini" > "$ddir/config.ini.new" 2>/dev/null \
    && mv "$ddir/config.ini.new" "$ddir/config.ini"
  # 重寫頂層 .ini 的路徑指向
  { echo "avd.ini.encoding=UTF-8"; echo "path=$ddir"; echo "path.rel=avd/$name.avd"
    grep '^target=' "$sini" 2>/dev/null; } > "$dini"
}

android_create_avd() {
  # 建一個名為 $1 的 AVD。先試 avdmanager（指定機型→最新 pixel），否則複製 fallback。
  local name="$1" did pkg tmpl
  if [ -n "$AVDMANAGER" ]; then
    pkg=$(android_latest_image) || { log "❌ 本機無任何已安裝的 Android system image，無法建 AVD。請先安裝（例：sdkmanager \"system-images;android-35;google_apis;arm64-v8a\"）"; return 2; }
    did=$(android_device_id_for "$DEVICE_ANDROID")
    if [ -z "$did" ]; then
      did=$(android_latest_pixel_id)
      [ -n "$did" ] && warn "找不到指定機型「${DEVICE_ANDROID}」，改用本機最新 Pixel device（id=${did}）"
    fi
    log "建立 AVD ${name}（image=$pkg${did:+, device=$did}）"
    if [ -n "$did" ]; then echo "no" | "$AVDMANAGER" create avd -n "$name" -k "$pkg" -d "$did" --force >&2 2>&1
    else                   echo "no" | "$AVDMANAGER" create avd -n "$name" -k "$pkg" --force >&2 2>&1; fi
    return $?
  fi
  # 無 avdmanager → 複製現有 AVD
  tmpl=$(android_pick_clone_template "$PREFIX")
  [ -n "$tmpl" ] || { log "❌ 無法自動建 AVD：本機無 cmdline-tools（avdmanager），也無可複製的現有模擬器。請用 Android Studio 先建一台，或安裝 cmdline-tools 後重試。"; return 2; }
  warn "本機無 avdmanager → 複製現有 AVD「${tmpl}」(本機最新機型) 建立 $name"
  android_clone_avd "$tmpl" "$name"
}

android_ensure_one() {
  # 確保名為 $1 的 pool AVD 存在且開機，回傳 serial
  local name="$1" serial
  if ! android_list_avds | grep -qx "$name"; then
    android_create_avd "$name" || return $?
  fi
  serial=$(android_serial_for_avd "$name") || serial=""
  if [ -n "$serial" ] && android_is_booted "$serial"; then printf '%s' "$serial"; return 0; fi
  if [ -z "$serial" ]; then
    local port; port=$(android_free_port) || { warn "無空閒 emulator port"; return 1; }
    log "開機 ${name}（port ${port}）"
    nohup "$EMULATOR" -avd "$name" -port "$port" -no-snapshot -no-boot-anim -gpu auto >/dev/null 2>&1 &
    serial="emulator-$port"
  fi
  android_wait_boot "$serial" || { warn "$name 開機逾時（${BOOT_TIMEOUT}s）"; return 1; }
  printf '%s' "$serial"
}

android_preflight() {
  android_resolve_tools
  [ -n "$A_SDK" ]    || die "找不到 Android SDK（無 ANDROID_HOME/ANDROID_SDK_ROOT，常見路徑也無）。請安裝 Android SDK。"
  [ -n "$ADB" ]      || die "找不到 adb。請安裝 Android SDK platform-tools。"
  [ -n "$EMULATOR" ] || die "找不到 emulator。請安裝 Android SDK emulator 套件。"
}

android_teardown() {
  android_resolve_tools
  [ -n "$ADB" ] || { warn "無 adb，略過 Android teardown"; return 0; }
  local s nm
  for s in $("$ADB" devices 2>/dev/null | awk '/emulator-.*device$/{print $1}'); do
    nm=$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')
    case "$nm" in "$PREFIX"*) log "關機 $nm ($s)（保留 profile）"; "$ADB" -s "$s" emu kill >/dev/null 2>&1;; esac
  done
}

# ============================ iOS ============================
ios_preflight() {
  have xcrun || die "找不到 xcrun（本機非 macOS 或未裝 Xcode command line tools）。iOS 模擬器只能在 macOS + Xcode 上跑。"
  xcrun simctl help >/dev/null 2>&1 || die "xcrun simctl 不可用。請安裝 Xcode 並執行 xcode-select --install。"
}

ios_list_pool() {
  # 印 pool 裝置：name<TAB>udid<TAB>state（只列 available runtime 下的）
  xcrun simctl list devices available 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      *"$PREFIX"*"("*)
        nm=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*//; s/ \(.*//')
        case "$nm" in "$PREFIX"*) ;; *) continue;; esac
        udid=$(printf '%s' "$line" | grep -oE '[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}' | head -1)
        st=$(printf '%s' "$line" | grep -oE '\((Booted|Booting|Shutdown|Shutting Down)\)' | tail -1 | tr -d '()')
        [ -n "$udid" ] && printf '%s\t%s\t%s\n' "$nm" "$udid" "$st"
        ;;
    esac
  done
}

ios_udid_for() { ios_list_pool | awk -F'\t' -v n="$1" '$1==n{print $2; exit}'; }

ios_devicetype_id() {
  # 精確機型名 → SimDeviceType id（避免 "iPhone 16" 誤中 "iPhone 16 Pro"）
  xcrun simctl list devicetypes 2>/dev/null \
    | sed -nE "s/^$1 \((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]*)\)\$/\1/p" | head -1
}

ios_latest_iphone_id() {
  xcrun simctl list devicetypes 2>/dev/null \
    | sed -nE 's/^(iPhone [0-9][^(]*) \((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]*)\)$/\1|\2/p' \
    | sort -t'|' -k1 -V | tail -1 | cut -d'|' -f2
}

ios_latest_runtime_id() {
  xcrun simctl list runtimes 2>/dev/null \
    | sed -nE 's/^iOS ([0-9.]+) .*(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+).*$/\1|\2/p' \
    | sort -t'|' -k1 -V | tail -1 | cut -d'|' -f2
}

ios_create() {
  local name="$1" dt rt
  dt=$(ios_devicetype_id "$DEVICE_IOS")
  if [ -z "$dt" ]; then
    dt=$(ios_latest_iphone_id)
    [ -n "$dt" ] && warn "找不到指定機型「${DEVICE_IOS}」，改用本機最新 iPhone device type（${dt}）"
  fi
  [ -n "$dt" ] || { log "❌ 本機無任何 iPhone 模擬器機型。請在 Xcode 安裝。"; return 2; }
  rt=$(ios_latest_runtime_id)
  [ -n "$rt" ] || { log "❌ 本機無任何 iOS simulator runtime。請在 Xcode > Settings > Components 安裝 iOS runtime。"; return 2; }
  log "建立 simulator ${name}（device=$dt, runtime=${rt}）"
  xcrun simctl create "$name" "$dt" "$rt"   # stdout = udid
}

ios_ensure_one() {
  local name="$1" udid rc
  udid=$(ios_udid_for "$name")
  if [ -z "$udid" ]; then udid=$(ios_create "$name"); rc=$?; [ "$rc" -ne 0 ] && return "$rc"; fi
  log "開機 ${name}（${udid}）"
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || { warn "$name 開機失敗"; return 1; }
  printf '%s' "$udid"
}

ios_teardown() {
  ios_preflight 2>/dev/null || { warn "無 xcrun，略過 iOS teardown"; return 0; }
  ios_list_pool | while IFS=$'\t' read -r nm udid st; do
    case "$st" in Booted|Booting) log "關機 $nm ($udid)（保留 profile）"; xcrun simctl shutdown "$udid" >/dev/null 2>&1;; esac
  done
}

# ============================ main ============================
while [ $# -gt 0 ]; do
  case "$1" in
    --platform)       PLATFORM="${2:-}"; shift 2;;
    --count)          COUNT="${2:-}"; shift 2;;
    --prefix)         PREFIX="${2:-}"; shift 2;;
    --device-android) DEVICE_ANDROID="${2:-}"; shift 2;;
    --device-ios)     DEVICE_IOS="${2:-}"; shift 2;;
    --teardown)       MODE="teardown"; shift;;
    --boot-timeout)   BOOT_TIMEOUT="${2:-}"; shift 2;;
    -h|--help)        usage;;
    *) log "未知參數：$1"; usage;;
  esac
done

[ -n "$PLATFORM" ] || PLATFORM=$(detect_platform)
case "$PLATFORM" in android|ios) ;; *) die "無法判定平台。請傳 --platform android|ios（cwd 也偵測不到 repo 特徵）";; esac

if [ "$MODE" = "teardown" ]; then
  log "screen-mender · teardown pool「${PREFIX}」· 平台 $PLATFORM"
  [ "$PLATFORM" = android ] && android_teardown
  [ "$PLATFORM" = ios ]     && ios_teardown
  exit 0
fi

case "$COUNT" in ''|*[!0-9]*) die "--count 需為正整數（拿到：'$COUNT'）";; esac
[ "$COUNT" -ge 1 ] || die "--count 需 ≥ 1"

log "screen-mender 裝置自動準備 · 平台 $PLATFORM · 目標 $COUNT 台 · 命名 ${PREFIX}NN"
[ "$PLATFORM" = android ] && android_preflight
[ "$PLATFORM" = ios ]     && ios_preflight

READY=()
n=1
while [ "$n" -le "$COUNT" ]; do
  name="${PREFIX}$(pad2 "$n")"
  if [ "$PLATFORM" = android ]; then serial=$(android_ensure_one "$name"); rc=$?
  else                               serial=$(ios_ensure_one "$name");     rc=$?; fi
  if [ "$rc" -eq 0 ] && [ -n "$serial" ]; then READY+=("$serial"); log "✅ $name → $serial ready"
  elif [ "$rc" -eq 2 ]; then warn "環境無法再自動建更多裝置（見上）→ 停止補建，改用已備妥的"; break
  else warn "$name 準備失敗，跳過"; fi
  n=$((n+1))
done

got=${#READY[@]}
[ "$got" -ge 1 ] || die "零台裝置可用（目標 ${COUNT}）。請依上方訊息補齊環境後重試。"
[ "$got" -lt "$COUNT" ] && warn "只備妥 $got/$COUNT 台 → orchestrator 應降為 $got 條 lane（不靜默縮水）"
log "ready: $got/$COUNT"
printf '%s\n' "${READY[@]}"   # stdout：每行一個 serial/udid
exit 0
