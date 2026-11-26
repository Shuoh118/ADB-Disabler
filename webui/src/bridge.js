// Bridge between the WebUI and the module manager's root shell.
//
// The one API shared by all three managers is KernelSU's WebView bridge:
// `window.ksu.exec(command, optionsJson, callbackName)` — KernelSU, APatch and
// MMRL (for Magisk / KernelSU / APatch) all expose it. MMRL additionally
// requires the user to grant the "Advanced KernelSU API" permission; when that
// is missing we show an actionable notice instead of pretending to work.
//
// Outside a manager (plain browser) the UI runs against a simulated device so
// the layout and interactions can still be reviewed.

const win = typeof window === 'undefined' ? {} : window

const ksu = win.ksu
const mmrlApi = win.$adbdisabler
const mmrlAllowed = (() => {
  try {
    return mmrlApi && typeof mmrlApi.getHasAccessToAdvancedKernelSuAPI === 'function'
      ? mmrlApi.getHasAccessToAdvancedKernelSuAPI()
      : null
  } catch {
    return null
  }
})()

export const hasShell = Boolean(ksu && typeof ksu.exec === 'function')
export const isMMRL = Boolean(win.mmrl)
export const isDemo = !hasShell && !isMMRL
export const needsGrant = isMMRL && (!hasShell || mmrlAllowed === false)

function managerName() {
  if (isMMRL) {
    try {
      const root = win.mmrl?.getRootConfig?.()
      const platform = root?.getPlatform?.()
      if (platform && platform !== 'Unknown') return `MMRL · ${platform}`
    } catch {}
    return 'MMRL'
  }
  if (hasShell) return 'KernelSU'
  return '浏览器预览'
}

export const bridgeName = managerName()

/** MMRL follows the app theme, which can differ from the OS theme. */
export const mmrlDark = (() => {
  try {
    return mmrlApi && typeof mmrlApi.isDarkMode === 'function' ? mmrlApi.isDarkMode() : null
  } catch {
    return null
  }
})()

let callbackSeq = 0

function normalise(raw) {
  if (raw && typeof raw === 'object') {
    return {
      code: Number(raw.errno ?? raw.code ?? 0),
      out: String(raw.stdout ?? ''),
      err: String(raw.stderr ?? ''),
    }
  }
  return { code: 0, out: String(raw ?? ''), err: '' }
}

/**
 * Call the KernelSU bridge and normalise every shape we might get back:
 * callback (KSU / APatch / MMRL), promise (some KSU Next builds) or a plain
 * synchronous object (older hosting apps).
 */
function execShell(command) {
  return new Promise((resolve, reject) => {
    let settled = false
    let timer = null
    const callbackName = `__adbdisabler_${Date.now()}_${callbackSeq++}`

    const finish = (result) => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      try {
        delete win[callbackName]
      } catch {}
      resolve(result)
    }

    const fail = (error) => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      try {
        delete win[callbackName]
      } catch {}
      reject(error)
    }

    win[callbackName] = (errno, stdout, stderr) => {
      finish({
        code: Number(errno ?? 0),
        out: String(stdout ?? ''),
        err: String(stderr ?? ''),
      })
    }

    timer = setTimeout(() => fail(new Error('命令执行超时')), 20000)

    try {
      const returned = ksu.exec(command, JSON.stringify({}), callbackName)
      if (returned && typeof returned.then === 'function') {
        returned.then((value) => finish(normalise(value))).catch(fail)
      } else if (returned !== undefined) {
        finish(normalise(returned))
      }
    } catch (error) {
      fail(error)
    }
  })
}

export async function exec(command) {
  if (isDemo) return { code: 0, out: '', err: '' }
  if (!hasShell) {
    return {
      code: -1,
      out: '',
      err: '当前 WebUI 没有获得 root shell 权限，请在 MMRL 中允许「高级 KernelSU API」',
    }
  }
  try {
    return await execShell(command)
  } catch (error) {
    return { code: -1, out: '', err: String(error?.message ?? error) }
  }
}

/* ------------------------------------------------------------------ */
/* Shell commands                                                      */
/* ------------------------------------------------------------------ */

const PRELUDE = `
S=/system/bin/settings; [ -x "$S" ] || S=settings
G=/system/bin/getprop; [ -x "$G" ] || G=getprop
RP=
for p in /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop /data/adb/ap/bin/resetprop; do
  if [ -x "$p" ]; then RP="$p"; break; fi
done
if [ -z "$RP" ]; then RP="$(command -v resetprop 2>/dev/null)"; fi
rp() { if [ -n "$RP" ]; then "$RP" "$@"; fi; }
`

function action(body, label) {
  return `${PRELUDE}
${body}
_rc=$?
mkdir -p /data/adb/adbdisabler 2>/dev/null
printf '%s [webui] %s (rc=%s)\\n' "$(date '+%Y-%m-%d %H:%M:%S')" '${label}' "$_rc" >> /data/adb/adbdisabler/service.log 2>/dev/null
[ "$_rc" -eq 0 ] && date +%s > /data/adb/adbdisabler/last_run 2>/dev/null
exit $_rc`
}

const BODIES = {
  'adb:on': `
"$S" put global adb_enabled 0
rp -n service.adb.root 0
rp -n init.svc.adbd stopped
rp -n init.svc_debug_pid.adbd ""
setprop persist.sys.usb.config mtp 2>/dev/null
setprop sys.usb.config mtp 2>/dev/null
setprop ctl.stop adbd 2>/dev/null
stop adbd 2>/dev/null
true
`,
  'adb:off': `
"$S" put global development_settings_enabled 1
"$S" put global adb_enabled 1
rp -n persist.sys.development_settings_enabled 1
rp -n persist.sys.usb.config mtp,adb
setprop persist.sys.usb.config mtp,adb 2>/dev/null
setprop sys.usb.config mtp,adb 2>/dev/null
setprop ctl.restart adbd 2>/dev/null || setprop ctl.start adbd 2>/dev/null || true
true
`,
  'dev:on': `
"$S" put global development_settings_enabled 0
rp -n persist.sys.development_settings_enabled 0
`,
  'dev:off': `
"$S" put global development_settings_enabled 1
rp -n persist.sys.development_settings_enabled 1
`,
  'oem:on': `
rp -n sys.oem_unlock_allowed 0
rp -n ro.oem_unlock_supported 0
`,
  'oem:off': `
rp -n sys.oem_unlock_allowed 1
rp -n ro.oem_unlock_supported 1
`,
}

const LABELS = {
  'adb:on': 'adb protect=on',
  'adb:off': 'adb protect=off',
  'dev:on': 'dev-options protect=on',
  'dev:off': 'dev-options protect=off',
  'oem:on': 'oem-unlock protect=on',
  'oem:off': 'oem-unlock protect=off',
}

export const STATUS_CMD = `
MOD=
for d in /data/adb/modules/adbdisabler /data/adb/modules_update/adbdisabler /data/adb/ap/modules/adbdisabler /data/adb/ksu/modules/adbdisabler; do
  if [ -d "$d" ]; then MOD="$d"; break; fi
done
[ -n "$MOD" ] || MOD=/data/adb/modules/adbdisabler
S=/system/bin/settings; [ -x "$S" ] || S=settings
G=/system/bin/getprop; [ -x "$G" ] || G=getprop
RP=
for p in /data/adb/ksu/bin/resetprop /data/adb/magisk/resetprop /data/adb/ap/bin/resetprop; do
  if [ -x "$p" ]; then RP="$p"; break; fi
done
if [ -z "$RP" ]; then RP="$(command -v resetprop 2>/dev/null)"; fi
if [ -d /data/adb/ap ]; then MGR=APatch
elif [ -d /data/adb/ksu ]; then MGR=KernelSU
elif [ -d /data/adb/magisk ]; then MGR=Magisk
else MGR=Unknown
fi
echo "MODDIR=$MOD"
echo "MANAGER=$MGR"
echo "VERSION=$(sed -n 's/^version=//p' "$MOD/module.prop" 2>/dev/null | head -n 1)"
echo "NAME=$(sed -n 's/^name=//p' "$MOD/module.prop" 2>/dev/null | head -n 1)"
echo "ADB_ENABLED=$("$S" get global adb_enabled 2>/dev/null)"
echo "DEV_SETTINGS=$("$S" get global development_settings_enabled 2>/dev/null)"
echo "PERSIST_DEV=$("$G" persist.sys.development_settings_enabled 2>/dev/null)"
echo "RO_DEBUGGABLE=$("$G" ro.debuggable 2>/dev/null)"
echo "ADB_SECURE=$("$G" ro.adb.secure 2>/dev/null)"
echo "OEM_ALLOWED=$("$G" sys.oem_unlock_allowed 2>/dev/null)"
echo "OEM_SUPPORTED=$("$G" ro.oem_unlock_supported 2>/dev/null)"
echo "ADBD=$("$G" init.svc.adbd 2>/dev/null)"
echo "BOOT=$("$G" sys.boot_completed 2>/dev/null)"
echo "USB_CONFIG=$("$G" persist.sys.usb.config 2>/dev/null)"
echo "MODEL=$("$G" ro.product.marketname 2>/dev/null)"
echo "MODEL_ALT=$("$G" ro.product.model 2>/dev/null)"
echo "ANDROID=$("$G" ro.build.version.release 2>/dev/null)"
echo "SDK=$("$G" ro.build.version.sdk 2>/dev/null)"
echo "DISABLED=$([ -f "$MOD/disable" ] && echo 1 || echo 0)"
echo "SERVICE=$([ -f "$MOD/service.sh" ] && echo 1 || echo 0)"
echo "RESETPROP=$RP"
echo "UID=$(id -u 2>/dev/null)"
echo "LAST=$(cat /data/adb/adbdisabler/last_run 2>/dev/null)"
`

export function parseStatus(text) {
  const data = {}
  String(text ?? '')
    .split('\n')
    .forEach((line) => {
      const at = line.indexOf('=')
      if (at > 0) data[line.slice(0, at).trim()] = line.slice(at + 1).trim()
    })
  return data
}

export function setProtection(key, on) {
  if (isDemo) return demoSet(key, on)
  const id = `${key}:${on ? 'on' : 'off'}`
  return exec(action(BODIES[id], LABELS[id]))
}

export function sealAll() {
  if (isDemo) return demoSeal()
  return exec(`
for d in /data/adb/modules/adbdisabler /data/adb/modules_update/adbdisabler /data/adb/ap/modules/adbdisabler /data/adb/ksu/modules/adbdisabler; do
  if [ -f "$d/service.sh" ]; then
    sh "$d/service.sh" --now
    exit $?
  fi
done
echo "service.sh not found" >&2
exit 1
`)
}

export function readLog() {
  if (isDemo) return Promise.resolve({ code: 0, out: demoState.logs.join('\n'), err: '' })
  return exec(`
if [ -f /data/adb/adbdisabler/service.log ]; then
  tail -n 200 /data/adb/adbdisabler/service.log
fi
`)
}

export function clearLog() {
  if (isDemo) {
    demoState.logs = []
    return Promise.resolve({ code: 0, out: 'cleared', err: '' })
  }
  return exec(`
: > /data/adb/adbdisabler/service.log 2>/dev/null
printf '%s [webui] log cleared\\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> /data/adb/adbdisabler/service.log 2>/dev/null
echo cleared
`)
}

/* ------------------------------------------------------------------ */
/* Simulated device (browser preview)                                  */
/* ------------------------------------------------------------------ */

const now = () => Math.floor(Date.now() / 1000)

function stamp(epoch) {
  const d = new Date(epoch * 1000)
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}

const seededAt = now() - 8 * 60

export const demoState = {
  adb: true,
  dev: true,
  oem: true,
  lastRun: seededAt,
  logs: [
    `${stamp(seededAt)} [boot] start resetprop=/data/adb/ksu/bin/resetprop`,
    `${stamp(seededAt)} [boot] done adb=0 dev=0 oem=0`,
    `${stamp(seededAt)} [webui] opened from preview`,
  ],
}

function demoStatusText() {
  const on = (v) => (v ? '0' : '1')
  return [
    'MODDIR=/data/adb/modules/adbdisabler',
    'MANAGER=KernelSU',
    'VERSION=1.1.0',
    'NAME=ADB Disabler',
    `ADB_ENABLED=${on(demoState.adb)}`,
    `DEV_SETTINGS=${on(demoState.dev)}`,
    `PERSIST_DEV=${on(demoState.dev)}`,
    'RO_DEBUGGABLE=0',
    'ADB_SECURE=1',
    `OEM_ALLOWED=${on(demoState.oem)}`,
    `OEM_SUPPORTED=${on(demoState.oem)}`,
    `ADBD=${demoState.adb ? 'stopped' : 'running'}`,
    'BOOT=1',
    `USB_CONFIG=${demoState.adb ? 'mtp' : 'mtp,adb'}`,
    'MODEL=Xiaomi 15',
    'MODEL_ALT=24129PN74C',
    'ANDROID=16',
    'SDK=36',
    'DISABLED=0',
    'SERVICE=1',
    'RESETPROP=/data/adb/ksu/bin/resetprop',
    'UID=0',
    `LAST=${demoState.lastRun}`,
  ].join('\n')
}

export function demoReadStatus() {
  return Promise.resolve(parseStatus(demoStatusText()))
}

function demoLog(line) {
  demoState.logs.push(`${stamp(now())} [webui] ${line}`)
  if (demoState.logs.length > 200) demoState.logs = demoState.logs.slice(-200)
  demoState.lastRun = now()
}

function demoSet(key, on) {
  demoState[key] = Boolean(on)
  demoLog(`${key} protect=${on ? 'on' : 'off'} (simulated)`)
  return Promise.resolve({ code: 0, out: '', err: '' })
}

function demoSeal() {
  demoState.adb = true
  demoState.dev = true
  demoState.oem = true
  demoLog('seal all (simulated)')
  return Promise.resolve({ code: 0, out: '', err: '' })
}
