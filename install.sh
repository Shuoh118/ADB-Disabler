SKIPMOUNT=false
LATESTARTSERVICE=true
POSTFSDATA=false
PROPFILE=false

print_modname() {
  ui_print "*******************************"
  ui_print "  USB/OEM/开发者模式 禁用器"
  ui_print "                                                 "
  ui_print "你有时间去试错 也有时间去止损 但不应该拿时间去后悔"
  ui_print "*******************************"
}

on_install() {
  ui_print "- 安装开机禁用组件 (service.sh)..."
}

set_permissions() {
  set_perm_recursive $MODPATH 0 0 0755 0644
  set_perm $MODPATH/service.sh 0 0 0755
}
