#!/system/bin/sh
# 属性类改动，赶在 adbd 决策之前

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

[ -f "$MODDIR/disable" ] && exit 0

CONF="$MODDIR/config/adbdisabler.conf"

cfg_get() {
  [ -f "$CONF" ] || return 1
  sed -n "s/^$1=//p" "$CONF" 2>/dev/null | head -n 1 |
    sed 's/[[:space:]]*#.*$//' | tr -d '\r' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

DISABLE_ADB=$(cfg_get DISABLE_ADB)
DISABLE_OEM=$(cfg_get DISABLE_OEM_UNLOCK)
USB_PROFILE=$(cfg_get USB_PROFILE)

DISABLE_ADB=${DISABLE_ADB:-1}
DISABLE_OEM=${DISABLE_OEM:-1}
USB_PROFILE=${USB_PROFILE:-mtp}

RP=
for _c in resetprop \
          /data/adb/magisk/resetprop \
          /data/adb/ksu/bin/resetprop \
          /data/adb/ap/bin/resetprop; do
  if command -v "$_c" >/dev/null 2>&1; then RP=$_c; break; fi
  [ -x "$_c" ] && { RP=$_c; break; }
done
unset _c

set_ro() {
  _k=$1; _v=$2
  [ -n "$RP" ] || return 1
  "$RP" -n "$_k" "$_v" 2>/dev/null && return 0
  "$RP" "$_k" "$_v" 2>/dev/null && return 0
  return 1
}

if [ "$DISABLE_ADB" = "1" ]; then
  # ro.adb.secure=1 要求主机指纹确认；ro.debuggable=0 让 adbd 默认不起
  set_ro ro.adb.secure 1
  set_ro ro.debuggable 0
  set_ro ro.force.debuggable 0
  set_ro service.adb.root 0
fi

if [ "$DISABLE_OEM" = "1" ]; then
  set_ro sys.oem_unlock_allowed 0
  set_ro ro.oem_unlock_supported 0
fi

# 开机就让 gadget 以不含 adb 的组合成型
if [ -n "$USB_PROFILE" ] && [ "$USB_PROFILE" != "none" ]; then
  setprop persist.sys.usb.config "$USB_PROFILE" 2>/dev/null
  [ -n "$(getprop vendor.usb.config 2>/dev/null)" ] && \
    setprop vendor.usb.config "$USB_PROFILE" 2>/dev/null
fi

mkdir -p /data/adb/adbdisabler 2>/dev/null
chmod 0700 /data/adb/adbdisabler 2>/dev/null

exit 0
