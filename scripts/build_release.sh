#!/usr/bin/env bash
# 将 Flutter release 产物统一收集到项目根目录 output/<version>/ 。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="$(awk '/^name:/ { print $2; exit }' pubspec.yaml)"
VERSION="$(awk '/^version:/ { print $2; exit }' pubspec.yaml)"
SAFE_VERSION="${VERSION//+/-}"
MAC_APP_NAME="$(awk -F ' = ' '/^PRODUCT_NAME / { print $2; exit }' macos/Runner/Configs/AppInfo.xcconfig)"
MAC_APP_NAME="${MAC_APP_NAME:-PDFReader}"

OUTPUT_ROOT="$ROOT/output"
DEST="$OUTPUT_ROOT/$VERSION"
COPY_ONLY=0
PLATFORMS=()
FAILURES=()

usage() {
  cat <<EOF
用法: $(basename "$0") [选项] [平台...]

将 release 产物收集到:
  output/$VERSION/<platform>/

平台: android ios macos web windows linux
不指定平台时，按当前系统自动选择可构建的目标。

选项:
  --copy-only   不重新构建，只拷贝已有产物
  -h, --help    显示帮助

示例:
  $(basename "$0")
  $(basename "$0") android macos web
  $(basename "$0") --copy-only web
EOF
}

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf '警告: %s\n' "$*" >&2
}

fail_platform() {
  local platform="$1"
  shift
  warn "$platform: $*"
  FAILURES+=("$platform")
}

has_android_sdk() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [[ -n "$sdk" && -d "$sdk" ]] || [[ -d "$HOME/Library/Android/sdk" ]] || [[ -d "$HOME/Android/Sdk" ]]
}

auto_platforms() {
  local list=(web)
  case "$(uname -s)" in
    Darwin)
      list+=(macos)
      if command -v xcodebuild >/dev/null 2>&1; then
        list+=(ios)
      fi
      if has_android_sdk; then
        list+=(android)
      fi
      ;;
    Linux)
      list+=(linux)
      if has_android_sdk; then
        list+=(android)
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      list+=(windows)
      if has_android_sdk; then
        list+=(android)
      fi
      ;;
  esac
  printf '%s\n' "${list[@]}"
}

prepare_dir() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
}

copy_file() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$src" ]]; then
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
}

copy_tree() {
  local src="$1"
  local dest="$2"
  if [[ ! -e "$src" ]]; then
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  if command -v ditto >/dev/null 2>&1; then
    ditto "$src" "$dest"
  else
    cp -R "$src" "$dest"
  fi
}

build_android() {
  local out="$DEST/android"
  prepare_dir "$out"

  if [[ "$COPY_ONLY" -eq 0 ]]; then
    log "构建 Android APK / AAB"
    flutter build apk --release
    flutter build appbundle --release
  fi

  local copied=0
  if copy_file build/app/outputs/flutter-apk/app-release.apk "$out/${APP_NAME}-${SAFE_VERSION}.apk"; then
    copied=1
  fi
  if copy_file build/app/outputs/bundle/release/app-release.aab "$out/${APP_NAME}-${SAFE_VERSION}.aab"; then
    copied=1
  fi
  if [[ "$copied" -eq 0 ]]; then
    fail_platform android "未找到 APK/AAB，请先成功执行 flutter build apk / appbundle"
    return
  fi
  log "Android 产物: $out"
}

build_ios() {
  local out="$DEST/ios"
  prepare_dir "$out"

  if [[ "$COPY_ONLY" -eq 0 ]]; then
    log "构建 iOS IPA"
    if ! flutter build ipa --release; then
      warn "IPA 构建失败，尝试构建未签名 .app"
      flutter build ios --release --no-codesign || {
        fail_platform ios "flutter build ipa / ios 失败"
        return
      }
    fi
  fi

  local copied=0
  local ipa
  shopt -s nullglob
  for ipa in build/ios/ipa/*.ipa; do
    copy_file "$ipa" "$out/${APP_NAME}-${SAFE_VERSION}.ipa"
    copied=1
  done
  shopt -u nullglob

  if [[ "$copied" -eq 0 ]]; then
    if copy_tree build/ios/iphoneos/Runner.app "$out/Runner.app"; then
      copied=1
      warn "未找到 IPA，已拷贝 Runner.app（需在 Xcode 中签名导出）"
    fi
  fi
  if [[ "$copied" -eq 0 ]]; then
    fail_platform ios "未找到 IPA 或 Runner.app"
    return
  fi
  log "iOS 产物: $out"
}

build_macos() {
  local out="$DEST/macos"
  prepare_dir "$out"

  if [[ "$COPY_ONLY" -eq 0 ]]; then
    log "构建 macOS"
    flutter build macos --release
  fi

  local app="build/macos/Build/Products/Release/${MAC_APP_NAME}.app"
  if ! copy_tree "$app" "$out/${MAC_APP_NAME}.app"; then
    fail_platform macos "未找到 $app"
    return
  fi
  if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$out/${MAC_APP_NAME}.app" "$out/${MAC_APP_NAME}-${SAFE_VERSION}.zip"
  fi
  log "macOS 产物: $out"
}

build_web() {
  local out="$DEST/web"
  prepare_dir "$out"

  if [[ "$COPY_ONLY" -eq 0 ]]; then
    log "构建 Web"
    flutter build web --release --output "$out"
  else
    if ! copy_tree build/web "$out"; then
      fail_platform web "未找到 build/web"
      return
    fi
  fi
  log "Web 产物: $out"
}

build_windows() {
  local out="$DEST/windows"
  prepare_dir "$out"

  if [[ "$COPY_ONLY" -eq 0 ]]; then
    log "构建 Windows"
    flutter build windows --release
  fi

  local src=""
  if [[ -d build/windows/x64/runner/Release ]]; then
    src=build/windows/x64/runner/Release
  elif [[ -d build/windows/runner/Release ]]; then
    src=build/windows/runner/Release
  fi
  if [[ -z "$src" ]] || ! copy_tree "$src" "$out"; then
    fail_platform windows "未找到 Windows Release 目录"
    return
  fi
  log "Windows 产物: $out"
}

build_linux() {
  local out="$DEST/linux"
  prepare_dir "$out"

  if [[ "$COPY_ONLY" -eq 0 ]]; then
    log "构建 Linux"
    flutter build linux --release
  fi

  local src=""
  if [[ -d build/linux/x64/release/bundle ]]; then
    src=build/linux/x64/release/bundle
  elif [[ -d build/linux/arm64/release/bundle ]]; then
    src=build/linux/arm64/release/bundle
  fi
  if [[ -z "$src" ]] || ! copy_tree "$src" "$out"; then
    fail_platform linux "未找到 Linux bundle 目录"
    return
  fi
  log "Linux 产物: $out"
}

run_platform() {
  case "$1" in
    android) build_android ;;
    ios) build_ios ;;
    macos) build_macos ;;
    web) build_web ;;
    windows) build_windows ;;
    linux) build_linux ;;
    *)
      warn "未知平台: $1"
      FAILURES+=("$1")
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --copy-only)
      COPY_ONLY=1
      shift
      ;;
    --)
      shift
      PLATFORMS+=("$@")
      break
      ;;
    -*)
      warn "未知选项: $1"
      usage >&2
      exit 2
      ;;
    *)
      PLATFORMS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
  while IFS= read -r platform; do
    PLATFORMS+=("$platform")
  done < <(auto_platforms)
fi

mkdir -p "$DEST"
log "应用: $APP_NAME  版本: $VERSION"
log "输出目录: $DEST"
log "平台: ${PLATFORMS[*]}"

if [[ "$COPY_ONLY" -eq 0 ]]; then
  flutter pub get
fi

for platform in "${PLATFORMS[@]}"; do
  run_platform "$platform"
done

echo
log "完成，产物列表:"
if command -v find >/dev/null 2>&1; then
  find "$DEST" \( -type f -o -name '*.app' \) | sort
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo
  warn "以下平台失败: ${FAILURES[*]}"
  exit 1
fi
