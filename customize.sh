#!/system/bin/sh
# Magisk / KernelSU / APatch 共用安装钩子

command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

case "$0" in
  */*) _self=${0%/*} ;;
  *)   _self=$(pwd) ;;
esac
MODPATH=${MODPATH:-$_self}

[ -f "$MODPATH/module.prop" ] || {
  ui_print "! module.prop 缺失，安装中止"
  exit 1
}

MODID=$(sed -n 's/^id=//p' "$MODPATH/module.prop" | head -n 1 | tr -d '\r ')
MODVER=$(sed -n 's/^version=//p' "$MODPATH/module.prop" | head -n 1 | tr -d '\r ')

if [ -n "${KSU:-}" ] || [ -d /data/adb/ksu ]; then
  ROOT_SOL=KernelSU
elif [ -n "${APATCH:-}" ] || [ -d /data/adb/ap ]; then
  ROOT_SOL=APatch
elif [ -n "${MAGISK_VER_CODE:-}" ] || [ -d /data/adb/magisk ]; then
  ROOT_SOL=Magisk
else
  ROOT_SOL=Unknown
fi

ui_print "*******************************"
ui_print "  ADB Disabler $MODVER"
ui_print "  管理器: $ROOT_SOL"
ui_print "*******************************"
ui_print "- 安装开机禁用组件"

# 不复用 set_perm_recursive，三家签名不一致
chown -R 0:0 "$MODPATH" 2>/dev/null
find "$MODPATH" -type d -exec chmod 0755 {} \; 2>/dev/null
find "$MODPATH" -type f -exec chmod 0644 {} \; 2>/dev/null

# 必须可执行，否则管理器跳过
for f in service.sh post-fs-data.sh uninstall.sh action.sh customize.sh install.sh; do
  [ -f "$MODPATH/$f" ] && chmod 0755 "$MODPATH/$f"
done

chmod 0644 "$MODPATH/module.prop" 2>/dev/null
[ -f "$MODPATH/module.yaml" ] && chmod 0644 "$MODPATH/module.yaml"
[ -d "$MODPATH/config" ] && chmod 0755 "$MODPATH/config"
[ -f "$MODPATH/config/adbdisabler.conf" ] && chmod 0600 "$MODPATH/config/adbdisabler.conf"

# 旧 id 同时跑会互相覆盖，先清掉
OLD=/data/adb/modules/adblocked
if [ "$MODID" != "adblocked" ] && [ -d "$OLD" ]; then
  ui_print "- 清理旧模块 adblocked"
  rm -f "$OLD/disable" 2>/dev/null
  rm -rf "$OLD" 2>/dev/null
fi

mkdir -p /data/adb/adbdisabler 2>/dev/null
chown 0:0 /data/adb/adbdisabler 2>/dev/null
chmod 0700 /data/adb/adbdisabler 2>/dev/null

RP=
for _c in /data/adb/magisk/resetprop /data/adb/ksu/bin/resetprop /data/adb/ap/bin/resetprop resetprop; do
  if command -v "$_c" >/dev/null 2>&1 || [ -x "$_c" ]; then RP=$_c; break; fi
done

[ -n "$RP" ] && ui_print "- resetprop : $RP" || ui_print "! resetprop 缺失，ro.* 改不了"
[ -x /system/bin/settings ] && ui_print "- settings  : ok" || ui_print "! settings 缺失"
[ -x /system/bin/svc ] && ui_print "- svc       : ok" || ui_print "! svc 缺失"

[ -f "$MODPATH/disable" ] && rm -f "$MODPATH/disable"

ui_print "- 已安装到 $MODPATH"
ui_print "- 重启生效"
