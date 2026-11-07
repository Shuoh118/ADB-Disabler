#!/system/bin/sh
# post-fs-data 管属性，这里管 settings / svc / ctl，并常驻巡检

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

[ -f "$MODDIR/disable" ] && exit 0

CONF="$MODDIR/config/adbdisabler.conf"
STATEDIR=/data/adb/adbdisabler
LOGFILE=$STATEDIR/adbdisabler.log
mkdir -p "$STATEDIR" 2>/dev/null
chmod 0700 "$STATEDIR" 2>/dev/null

cfg_get() {
  [ -f "$CONF" ] || return 1
  sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n 1 |
    sed 's/[[:space:]]*#.*$//' | tr -d '\r' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

DISABLE_ADB=$(cfg_get DISABLE_ADB)
DISABLE_DEV=$(cfg_get DISABLE_DEVELOPER)
DISABLE_OEM=$(cfg_get DISABLE_OEM_UNLOCK)
USB_PROFILE=$(cfg_get USB_PROFILE)
WATCH=$(cfg_get WATCHDOG)
WATCH_INTERVAL=$(cfg_get WATCH_INTERVAL)
LOG_MAX_KB=$(cfg_get LOG_MAX_KB)

DISABLE_ADB=${DISABLE_ADB:-1}
DISABLE_DEV=${DISABLE_DEV:-1}
DISABLE_OEM=${DISABLE_OEM:-1}
USB_PROFILE=${USB_PROFILE:-mtp}
WATCH=${WATCH:-1}
WATCH_INTERVAL=${WATCH_INTERVAL:-10}
LOG_MAX_KB=${LOG_MAX_KB:-128}

log() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null
  _sz=$(wc -c < "$LOGFILE" 2>/dev/null | tr -d ' ')
  case "$_sz" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$_sz" -gt $(( LOG_MAX_KB * 1024 )) ] 2>/dev/null; then
    tail -c $(( LOG_MAX_KB * 512 )) "$LOGFILE" > "$LOGFILE.tmp" 2>/dev/null &&
      mv "$LOGFILE.tmp" "$LOGFILE"
  fi
}

# 三家 resetprop 路径不同，都不在 PATH 里
RP=
for _c in resetprop \
          /data/adb/magisk/resetprop \
          /data/adb/ksu/bin/resetprop \
          /data/adb/ap/bin/resetprop; do
  if command -v "$_c" >/dev/null 2>&1; then RP=$_c; break; fi
  [ -x "$_c" ] && { RP=$_c; break; }
done
unset _c

SETTINGS=
for _c in settings /system/bin/settings /system/xbin/settings; do
  if command -v "$_c" >/dev/null 2>&1; then SETTINGS=$_c; break; fi
  [ -x "$_c" ] && { SETTINGS=$_c; break; }
done
unset _c

SVC=
for _c in svc /system/bin/svc /system/xbin/svc; do
  if command -v "$_c" >/dev/null 2>&1; then SVC=$_c; break; fi
  [ -x "$_c" ] && { SVC=$_c; break; }
done
unset _c

log "service start | resetprop=${RP:-none} settings=${SETTINGS:-none} svc=${SVC:-none}"

[ -n "$RP" ] || log "! resetprop 不可用，ro.* 已在 post-fs-data 处理"

# 最多等 180s，等不到也继续，watchdog 会补
_i=0
while [ "$_i" -lt 90 ]; do
  [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
  sleep 2
  _i=$((_i + 1))
done
log "boot_completed after $((_i * 2))s"

sleep 3

set_ro() {
  _k=$1; _v=$2
  [ -n "$RP" ] || return 1
  "$RP" -n "$_k" "$_v" 2>/dev/null && return 0
  "$RP" "$_k" "$_v" 2>/dev/null && return 0
  return 1
}

apply_adb_off() {
  _chg=0

  if [ -n "$SETTINGS" ]; then
    if [ "$("$SETTINGS" get global adb_enabled 2>/dev/null)" != "0" ]; then
      "$SETTINGS" put global adb_enabled 0 2>/dev/null && _chg=1
    fi
  fi

  # 关开关只挡新连接，已跑的要停进程
  if [ "$(getprop init.svc.adbd 2>/dev/null)" = "running" ]; then
    setprop ctl.stop adbd 2>/dev/null && _chg=1
  fi

  set_ro ro.adb.secure 1
  set_ro service.adb.root 0
  set_ro ro.force.debuggable 0

  [ "$_chg" = "1" ] && log "adb off: applied"
  return 0
}

apply_dev_off() {
  [ -n "$SETTINGS" ] || return 1
  if [ "$("$SETTINGS" get global development_settings_enabled 2>/dev/null)" != "0" ]; then
    "$SETTINGS" put global development_settings_enabled 0 2>/dev/null &&
      log "developer options: disabled"
  fi
  return 0
}

apply_oem_off() {
  set_ro sys.oem_unlock_allowed 0
  set_ro ro.oem_unlock_supported 0
  return 0
}

apply_usb_profile() {
  _want=$1
  [ -n "$_want" ] || return 1
  [ "$_want" = "none" ] && _want=""

  # 从 gadget 反推当前组合
  _cur=""
  for _f in /config/usb_gadget/*/configs/*/; do
    [ -d "$_f" ] || continue
    for _e in "$_f"*; do
      [ -e "$_e" ] || continue
      _n=$(basename "$_e")
      case "$_n" in bMaxPacketSize0|MaxPower|bmAttributes) continue ;; esac
      _n=${_n#ffs.}
      case "$_n" in
        mtp|ptp|rndis|midi|adb|hid|mass_storage)
          _cur=${_cur:+$_cur,}$_n ;;
      esac
    done
    break
  done

  # 组合里带 adb 就换掉，否则 USB 描述符会带 ADB 接口
  case ",$_cur," in
    *",adb,"*)
      if [ -n "$SVC" ]; then
        if [ -n "$_want" ]; then
          "$SVC" usb setFunctions "$_want" 2>/dev/null
        else
          "$SVC" usb setFunctions 2>/dev/null
        fi
        log "usb profile: $_cur -> ${_want:-<none>}"
      fi
      ;;
  esac
  return 0
}

apply_adb_off
[ "$DISABLE_DEV" = "1" ] && apply_dev_off
[ "$DISABLE_OEM" = "1" ] && apply_oem_off
apply_usb_profile "$USB_PROFILE"

log "initial pass done"

# 查状态而不是查事件，幂等
if [ "$WATCH" = "1" ]; then
  log "watchdog on, interval ${WATCH_INTERVAL}s"
  while :; do
    [ -f "$MODDIR/disable" ] && { log "disable flag, watchdog exit"; break; }

    sleep "$WATCH_INTERVAL" 2>/dev/null || sleep 10

    _need=0
    if [ "$DISABLE_ADB" = "1" ] && [ -n "$SETTINGS" ]; then
      [ "$("$SETTINGS" get global adb_enabled 2>/dev/null)" != "0" ] && _need=1
    fi
    [ "$(getprop init.svc.adbd 2>/dev/null)" = "running" ] && _need=1
    if [ "$DISABLE_DEV" = "1" ] && [ -n "$SETTINGS" ]; then
      [ "$("$SETTINGS" get global development_settings_enabled 2>/dev/null)" != "0" ] && _need=1
    fi

    if [ "$_need" = "1" ]; then
      log "drift detected, re-applying"
      apply_adb_off
      [ "$DISABLE_DEV" = "1" ] && apply_dev_off
      apply_usb_profile "$USB_PROFILE"
    fi
  done
fi

log "service exit"
exit 0
