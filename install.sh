#!/system/bin/sh
# 老管理器兜底，转发到 customize.sh

case "$0" in
  */*) _self=${0%/*} ;;
  *)   _self=$(pwd) ;;
esac

[ -f "$_self/customize.sh" ] || {
  echo "! customize.sh 缺失"
  exit 1
}

. "$_self/customize.sh"
