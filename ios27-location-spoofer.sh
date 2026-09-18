#!/usr/bin/env bash

set -euo pipefail

readonly PMD_VERSION="11.15.4"
PMD=()
DEVICE_ARGS=()

usage() {
  cat <<'EOF'
用法：
  ./ios27-location-spoofer.sh devices
  ./ios27-location-spoofer.sh prepare [--udid UDID]
  ./ios27-location-spoofer.sh set LATITUDE LONGITUDE [--udid UDID]
  ./ios27-location-spoofer.sh clear [--udid UDID]

示例：
  ./ios27-location-spoofer.sh prepare
  ./ios27-location-spoofer.sh set 39.9087 116.3975
  ./ios27-location-spoofer.sh clear

set 会保持前台会话；保持终端窗口打开，按 Ctrl+C 结束。
首次使用前请在 iPhone 打开 Developer Mode，并通过 USB 解锁、信任这台电脑。
EOF
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 2
}

resolve_pmd() {
  if command -v uvx >/dev/null 2>&1; then
    PMD=(uvx --from "pymobiledevice3==${PMD_VERSION}" pymobiledevice3)
  elif command -v pymobiledevice3 >/dev/null 2>&1; then
    PMD=(pymobiledevice3)
  elif command -v python3 >/dev/null 2>&1 && python3 -c 'import pymobiledevice3' >/dev/null 2>&1; then
    PMD=(python3 -m pymobiledevice3)
  else
    die "未找到 uvx 或 pymobiledevice3。请先运行 'brew install uv'，或 'python3 -m pip install -U pymobiledevice3'。"
  fi

  if [[ "${PMD[0]}" != "uvx" ]]; then
    installed_version="$("${PMD[@]}" version 2>/dev/null)" || die "无法读取 pymobiledevice3 版本"
    version_at_least "$installed_version" "$PMD_VERSION" || \
      die "pymobiledevice3 ${installed_version} 太旧；iOS 27 需要 ${PMD_VERSION} 或更高版本"
  fi
}

version_at_least() {
  awk -v actual="$1" -v required="$2" '
    BEGIN {
      split(actual, a, ".")
      split(required, r, ".")
      for (i = 1; i <= 3; i += 1) {
        if ((a[i] + 0) > (r[i] + 0)) exit 0
        if ((a[i] + 0) < (r[i] + 0)) exit 1
      }
      exit 0
    }
  '
}

parse_device_options() {
  DEVICE_ARGS=()
  while (($# > 0)); do
    case "$1" in
      --udid)
        (($# >= 2)) || die "--udid 后缺少设备 UDID"
        [[ -n "$2" ]] || die "设备 UDID 不能为空"
        DEVICE_ARGS=(--udid "$2")
        shift 2
        ;;
      *)
        die "未知参数：$1"
        ;;
    esac
  done
}

is_number() {
  [[ "$1" =~ ^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]
}

in_range() {
  awk -v value="$1" -v lower="$2" -v upper="$3" \
    'BEGIN { exit !(value >= lower && value <= upper) }'
}

command_name="${1:-help}"
if (($# > 0)); then
  shift
fi

case "$command_name" in
  help|-h|--help)
    usage
    ;;
  devices)
    (($# == 0)) || die "devices 不接受其他参数"
    resolve_pmd
    "${PMD[@]}" usbmux list --usb
    ;;
  prepare)
    parse_device_options "$@"
    resolve_pmd
    printf '%s\n' "请确认 iPhone 已解锁、已信任电脑，并已在“设置 → 隐私与安全性 → Developer Mode”中开启开发者模式。"
    "${PMD[@]}" usbmux list --usb
    "${PMD[@]}" amfi developer-mode-status "${DEVICE_ARGS[@]:0}"
    "${PMD[@]}" mounter auto-mount "${DEVICE_ARGS[@]:0}"
    ;;
  set)
    (($# >= 2)) || die "set 需要纬度和经度"
    latitude="$1"
    longitude="$2"
    shift 2
    parse_device_options "$@"
    is_number "$latitude" || die "纬度不是有效数字：$latitude"
    is_number "$longitude" || die "经度不是有效数字：$longitude"
    in_range "$latitude" -90 90 || die "纬度必须在 -90 到 90 之间"
    in_range "$longitude" -180 180 || die "经度必须在 -180 到 180 之间"
    resolve_pmd
    printf '设置模拟定位：%s, %s\n' "$latitude" "$longitude"
    printf '%s\n' "保持此终端窗口打开；按 Ctrl+C 结束后，请运行 clear 恢复真实定位。"
    exec "${PMD[@]}" developer dvt simulate-location set "${DEVICE_ARGS[@]:0}" -- "$latitude" "$longitude"
    ;;
  clear)
    parse_device_options "$@"
    resolve_pmd
    "${PMD[@]}" developer dvt simulate-location clear "${DEVICE_ARGS[@]:0}"
    printf '%s\n' "已请求恢复真实定位。"
    ;;
  *)
    usage >&2
    die "未知命令：$command_name"
    ;;
esac
