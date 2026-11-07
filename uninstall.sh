#!/system/bin/sh
# 还原属性，删运行目录

case "$0" in
  */*) MODDIR=${0%/*} ;;
  *)   MODDIR=$(pwd) ;;
esac

RP=
for _c in resetprop \
          /data/adb/magisk/resetprop \
          /data/adb/ksu/bin/resetprop \
          /data/adb/ap/bin/resetprop; do
  if command -v "$_c" >/dev/null 2>&1; then RP=$_c; break; fi
  [ -x "$_c" ] && { RP=$_c; break; }
done
unset _c

if [ -n "$RP" ]; then
  "$RP" -n ro.adb.secure 1 2>/dev/null
  "$RP" -n sys.oem_unlock_allowed 1 2>/dev/null
  "$RP" -n ro.oem_unlock_supported 1 2>/dev/null
fi

rm -rf /data/adb/adbdisabler
rm -rf /data/adb/modules/adblocked 2>/dev/null

exit 0
