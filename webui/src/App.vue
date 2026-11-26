<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue'
import {
  MiuixArrowPreference,
  MiuixBottomSheet,
  MiuixButton,
  MiuixCard,
  MiuixDialog,
  MiuixDivider,
  MiuixIcon,
  MiuixIconButton,
  MiuixSmallTitle,
  MiuixSnackbarHost,
  MiuixSwitchPreference,
  dismissNewestSnackbar,
  setTheme,
  setThemeMode,
  showSnackbar,
  useTheme,
} from 'miuix-vue'
import {
  Copy,
  Delete,
  FavoritesFill,
  Info,
  Link,
  Lock,
  Notes,
  Refresh,
  Settings,
  Tune,
  Unlock,
} from 'miuix-vue/icons'
import iconUrl from './assets/mark.png'
import wechatQr from './assets/sponsor-wechat.png'
import alipayQr from './assets/sponsor-alipay.png'
import qqQr from './assets/sponsor-qq.png'
import {
  STATUS_CMD,
  bridgeName,
  clearLog,
  demoReadStatus,
  exec,
  isDemo,
  isMMRL,
  mmrlDark,
  needsGrant,
  parseStatus,
  readLog,
  sealAll,
  setProtection,
} from './bridge'

const THEME_KEY = 'adbdisabler.theme'
const THEME_META_COLOR = { light: '#f7f7f7', dark: '#000000' }
const RING = 2 * Math.PI * 23

const { theme } = useTheme()

try {
  const saved = localStorage.getItem(THEME_KEY)
  if (saved === 'light' || saved === 'dark') setTheme(saved)
  else if (mmrlDark !== null) setTheme(mmrlDark ? 'dark' : 'light')
  else setThemeMode('system')
} catch {
  setThemeMode('system')
}

watch(theme, (value) => {
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta) meta.setAttribute('content', THEME_META_COLOR[value] ?? THEME_META_COLOR.light)
})

const status = reactive({
  moddir: '',
  manager: '',
  version: '',
  name: '',
  adbEnabled: '',
  devSettings: '',
  persistDev: '',
  debuggable: '',
  adbSecure: '',
  oemAllowed: '',
  oemSupported: '',
  adbd: '',
  boot: '',
  usbConfig: '',
  model: '',
  modelAlt: '',
  android: '',
  sdk: '',
  disabled: '',
  service: '',
  resetprop: '',
  uid: '',
  lastRun: '',
})

const STATUS_MAP = {
  MODDIR: 'moddir',
  MANAGER: 'manager',
  VERSION: 'version',
  NAME: 'name',
  ADB_ENABLED: 'adbEnabled',
  DEV_SETTINGS: 'devSettings',
  PERSIST_DEV: 'persistDev',
  RO_DEBUGGABLE: 'debuggable',
  ADB_SECURE: 'adbSecure',
  OEM_ALLOWED: 'oemAllowed',
  OEM_SUPPORTED: 'oemSupported',
  ADBD: 'adbd',
  BOOT: 'boot',
  USB_CONFIG: 'usbConfig',
  MODEL: 'model',
  MODEL_ALT: 'modelAlt',
  ANDROID: 'android',
  SDK: 'sdk',
  DISABLED: 'disabled',
  SERVICE: 'service',
  RESETPROP: 'resetprop',
  UID: 'uid',
  LAST: 'lastRun',
}

function applyStatus(data) {
  for (const [key, prop] of Object.entries(STATUS_MAP)) {
    status[prop] = data[key] ?? ''
  }
}

const loading = ref(true)
const refreshing = ref(false)
const fatal = ref('')
const sealing = ref(false)
const nowTick = ref(Date.now())
const pending = reactive({})
const optimistic = reactive({})

async function refresh({ silent = false } = {}) {
  if (refreshing.value) return
  if (needsGrant) {
    loading.value = false
    return
  }
  refreshing.value = true
  if (!silent && !status.boot) loading.value = true

  try {
    if (isDemo) {
      applyStatus(await demoReadStatus())
    } else {
      const res = await exec(STATUS_CMD)
      if (res.code !== 0 && !res.out) {
        throw new Error(firstLine(res.err) || `状态查询失败（退出码 ${res.code}）`)
      }
      applyStatus(parseStatus(res.out))
    }
    fatal.value = ''
  } catch (error) {
    fatal.value = error?.message || '无法读取模块状态'
  } finally {
    refreshing.value = false
    loading.value = false
    nowTick.value = Date.now()
  }
}

const devEffective = computed(() =>
  status.devSettings && status.devSettings !== 'null'
    ? status.devSettings
    : status.persistDev,
)

const adbState = computed(() => {
  if (!status.boot) return 'unknown'
  if (status.adbEnabled === '0' && status.adbd !== 'running') return 'ok'
  if (status.adbEnabled === '1' || status.adbd === 'running') return 'open'
  return 'unknown'
})

const devState = computed(() => {
  if (devEffective.value === '0') return 'ok'
  if (devEffective.value === '1') return 'open'
  return 'unknown'
})

const oemState = computed(() => {
  if (status.oemAllowed === '0' || status.oemSupported === '0') return 'ok'
  if (status.oemAllowed === '1') return 'open'
  return 'unknown'
})

const items = computed(() => [
  {
    key: 'adb',
    title: 'USB 调试',
    summary: '关闭 USB 调试',
    short: 'ADB',
    icon: Link,
    tone: 'blue',
    state: adbState.value,
  },
  {
    key: 'dev',
    title: '开发者选项',
    summary: '关闭并隐藏设置中的开发者入口',
    short: '开发者',
    icon: Settings,
    tone: 'violet',
    state: devState.value,
  },
  {
    key: 'oem',
    title: 'OEM 解锁',
    summary: '关闭并在设置隐藏 OEM 解锁',
    short: 'OEM',
    icon: Unlock,
    tone: 'orange',
    state: oemState.value,
  },
])

const sealedCount = computed(() => items.value.filter((item) => item.state === 'ok').length)

const hasUnknown = computed(() => items.value.some((item) => item.state === 'unknown'))

const posture = computed(() => {
  if (loading.value || hasUnknown.value) return 'unknown'
  if (sealedCount.value === 3) return 'ok'
  if (sealedCount.value === 2) return 'two'
  if (sealedCount.value === 0) return 'closed'
  return 'partial'
})

const CN_NUM = ['零', '一', '二', '三']

const headline = computed(() => {
  if (loading.value) return '正在读取'
  if (hasUnknown.value) return '状态未知'
  const count = sealedCount.value
  if (count === 0) return '已关闭'
  if (count === 3) return '全部已开启'
  return `已开启${CN_NUM[count]}项`
})

const subline = computed(() => {
  if (loading.value) return '正在通过模块管理器读取系统属性…'
  if (hasUnknown.value) return '部分属性无法读取，请确认 root 权限'
  const count = sealedCount.value
  if (count === 0) return '三项防护全部关闭，设备处于可调试状态'
  if (count < 3) return `已开启${CN_NUM[count]}项，仍有${CN_NUM[3 - count]}项未开启`
  return 'ADB、开发者选项与 OEM 解锁均处于拦截状态'
})

const ringOffset = computed(() => RING * (1 - sealedCount.value / 3))

const busy = computed(
  () => sealing.value || Object.keys(pending).some((key) => pending[key]),
)

const moduleVersion = computed(() => status.version || '1.1.0')
const deviceModel = computed(() => status.model || status.modelAlt || '未知设备')

const environmentText = computed(() => {
  if (isDemo) return '浏览器预览'
  if (status.manager && status.manager !== 'Unknown') return status.manager
  return isMMRL ? 'MMRL' : bridgeName
})

const autoStartText = computed(() => {
  if (status.disabled === '1') return '模块已停用'
  if (status.service === '0') return '缺少 service.sh'
  return '开机自动执行'
})

const lastRunText = computed(() => relativeTime(status.lastRun))

const diagnostics = computed(() => [
  ['运行环境', environmentText.value],
  ['WebUI 接口', isDemo ? '无（模拟数据）' : isMMRL ? 'KernelSU API · MMRL' : 'KernelSU API'],
  ['UID', status.uid || '—'],
  ['模块目录', status.moddir || '—'],
  ['模块版本', moduleVersion.value],
  ['开机自启', autoStartText.value],
  ['resetprop', status.resetprop || '未找到'],
  ['ro.debuggable', status.debuggable || '—'],
  ['ro.adb.secure', status.adbSecure || '—'],
  ['adb_enabled', status.adbEnabled || '—'],
  ['development_settings_enabled', status.devSettings || '—'],
  ['persist.sys.development_settings_enabled', status.persistDev || '—'],
  ['sys.oem_unlock_allowed', status.oemAllowed || '—'],
  ['ro.oem_unlock_supported', status.oemSupported || '—'],
  ['init.svc.adbd', status.adbd || '—'],
  ['sys.boot_completed', status.boot || '—'],
  ['persist.sys.usb.config', status.usbConfig || '—'],
  ['设备', `${deviceModel.value} · Android ${status.android || '—'} (SDK ${status.sdk || '—'})`],
  ['上次执行', lastRunText.value],
])

const logSheet = ref(false)
const diagSheet = ref(false)
const sponsorOpen = ref(false)
const sponsorMethod = ref('wechat')
const heartPopping = ref(false)
const logText = ref('')
const logLoading = ref(false)
let heartTimer = null

const sponsorMethods = [
  { id: 'wechat', label: '微信', hint: '打开微信扫一扫', image: wechatQr },
  { id: 'alipay', label: '支付宝', hint: '打开支付宝扫一扫', image: alipayQr },
  { id: 'qq', label: 'QQ', hint: '用 QQ 扫一扫', image: qqQr },
]

const currentSponsor = computed(
  () => sponsorMethods.find((method) => method.id === sponsorMethod.value) ?? sponsorMethods[0],
)

const confirmState = reactive({
  open: false,
  title: '',
  summary: '',
  confirmText: '确认',
  danger: false,
  action: null,
})

function askConfirm(options) {
  dismissNewestSnackbar()
  Object.assign(confirmState, {
    open: true,
    title: '',
    summary: '',
    confirmText: '确认',
    danger: false,
    action: null,
    ...options,
  })
}

async function runConfirm() {
  const action = confirmState.action
  confirmState.open = false
  if (action) await action()
}

const stateText = (state) =>
  state === 'ok' ? '已拦截' : state === 'open' ? '未拦截' : '未知'

const isChecked = (item) =>
  item.key in optimistic ? optimistic[item.key] : item.state === 'ok'

function onToggle(item, value) {
  if (pending[item.key] || busy.value) return

  if (!value) {
    askConfirm({
      title: `关闭「${item.title}」防护？`,
      summary: '该操作会立即放开这项防护，直到下次开机由 service.sh 重新启用。',
      confirmText: '仍然关闭',
      danger: true,
      action: () => applyProtection(item.key, false),
    })
    return
  }
  applyProtection(item.key, true)
}

async function applyProtection(key, on) {
  const item = items.value.find((entry) => entry.key === key)
  if (!item) return

  pending[key] = true
  optimistic[key] = on

  try {
    const res = await setProtection(key, on)
    if (res.code !== 0) {
      throw new Error(firstLine(res.err) || `退出码 ${res.code}`)
    }
    showSnackbar({
      message:
        key === 'adb' && !on
          ? 'USB 调试已放开，开发者选项同时启用'
          : `${item.title}已${on ? '开启防护' : '放开'}`,
      duration: 'short',
    })
  } catch (error) {
    showSnackbar({
      message: `${item.title}操作失败：${shortError(error)}`,
      duration: 'long',
    })
  } finally {
    delete optimistic[key]
    pending[key] = false
    await delay(on ? 450 : 250)
    await refresh({ silent: true })
  }
}

async function sealNow() {
  if (busy.value) return
  sealing.value = true
  try {
    const res = await sealAll()
    if (res.code !== 0) throw new Error(firstLine(res.err) || `退出码 ${res.code}`)
    showSnackbar({ message: '已重新启用全部防护', duration: 'short' })
  } catch (error) {
    showSnackbar({ message: `启用失败：${shortError(error)}`, duration: 'long' })
  } finally {
    sealing.value = false
    await delay(600)
    await refresh({ silent: true })
  }
}

function openLog() {
  dismissNewestSnackbar()
  logSheet.value = true
  refreshLog()
}

function openDiag() {
  dismissNewestSnackbar()
  diagSheet.value = true
}

async function refreshLog() {
  logLoading.value = true
  try {
    const res = await readLog()
    logText.value = String(res.out ?? '').trimEnd() || '暂无运行日志'
  } catch (error) {
    logText.value = `读取日志失败：${shortError(error)}`
  } finally {
    logLoading.value = false
  }
}

function askClearLog() {
  askConfirm({
    title: '清空运行日志？',
    summary: '将删除 /data/adb/adbdisabler/service.log 中的全部记录。',
    confirmText: '清空',
    danger: true,
    action: async () => {
      const res = await clearLog()
      if (res.code !== 0) {
        showSnackbar({ message: `清空失败：${firstLine(res.err) || res.code}`, duration: 'long' })
        return
      }
      await refreshLog()
      showSnackbar({ message: '运行日志已清空', duration: 'short' })
    },
  })
}

async function copyLog() {
  const ok = await copyText(logText.value)
  showSnackbar({ message: ok ? '日志已复制' : '复制失败，请手动选择文本', duration: 'short' })
}

async function copyDiag() {
  const text = diagnostics.value.map(([key, value]) => `${key}: ${value}`).join('\n')
  const ok = await copyText(text)
  showSnackbar({ message: ok ? '诊断信息已复制' : '复制失败，请手动选择文本', duration: 'short' })
}

function pulseHeart() {
  heartPopping.value = false
  requestAnimationFrame(() => {
    heartPopping.value = true
    clearTimeout(heartTimer)
    heartTimer = setTimeout(() => {
      heartPopping.value = false
    }, 520)
  })
  try {
    navigator.vibrate?.(10)
  } catch {}
}

async function copyText(text) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text)
      return true
    }
  } catch {}

  try {
    const area = document.createElement('textarea')
    area.value = text
    area.setAttribute('readonly', '')
    area.style.position = 'fixed'
    area.style.opacity = '0'
    document.body.appendChild(area)
    area.select()
    const ok = document.execCommand('copy')
    area.remove()
    return ok
  } catch {
    return false
  }
}

let themeTransitioning = false

async function applyTheme(next) {
  document.documentElement.classList.remove('m-theme-light')
  setTheme(next)
  try {
    localStorage.setItem(THEME_KEY, next)
  } catch {}
  await nextTick()
}

function themeOrigin(event) {
  const rect = event?.currentTarget?.getBoundingClientRect?.()
  const x = rect ? rect.left + rect.width / 2 : window.innerWidth - 44
  const y = rect ? rect.top + rect.height / 2 : 44
  const radius = Math.hypot(
    Math.max(x, window.innerWidth - x),
    Math.max(y, window.innerHeight - y),
  )
  return { x, y, radius }
}

function toggleTheme(event) {
  if (themeTransitioning) return
  const next = theme.value === 'dark' ? 'light' : 'dark'
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  if (reduceMotion) {
    applyTheme(next)
    return
  }

  const { x, y, radius } = themeOrigin(event)
  themeTransitioning = true

  if (typeof document.startViewTransition === 'function') {
    try {
      const transition = document.startViewTransition(() => applyTheme(next))
      transition.ready
        .then(() => {
          document.documentElement.animate(
            {
              clipPath: [
                `circle(0px at ${x}px ${y}px)`,
                `circle(${radius}px at ${x}px ${y}px)`,
              ],
            },
            {
              duration: 520,
              easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
              pseudoElement: '::view-transition-new(root)',
            },
          )
        })
        .catch(() => {})
      transition.finished.finally(() => {
        themeTransitioning = false
      })
      return
    } catch {
      themeTransitioning = false
    }
  }

  animateThemeCircle(next, x, y, radius)
}

function animateThemeCircle(next, x, y, radius) {
  const overlay = document.createElement('div')
  overlay.className = 'theme-wipe'
  overlay.style.background = next === 'dark' ? '#000' : '#f7f7f7'
  overlay.style.clipPath = `circle(0px at ${x}px ${y}px)`
  document.body.appendChild(overlay)

  const animation = overlay.animate(
    [
      { clipPath: `circle(0px at ${x}px ${y}px)` },
      { clipPath: `circle(${radius}px at ${x}px ${y}px)` },
    ],
    { duration: 520, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', fill: 'forwards' },
  )

  animation.finished
    .then(async () => {
      await applyTheme(next)
      overlay.classList.add('is-fading')
      window.setTimeout(() => {
        overlay.remove()
        themeTransitioning = false
      }, 240)
    })
    .catch(() => {
      overlay.remove()
      themeTransitioning = false
    })
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function firstLine(text) {
  return String(text ?? '').split('\n').map((line) => line.trim()).find(Boolean) ?? ''
}

function shortError(error) {
  const message = firstLine(error?.message ?? error) || '未知错误'
  return message.length > 90 ? `${message.slice(0, 90)}…` : message
}

function relativeTime(epoch) {
  const seconds = Number(epoch)
  if (!seconds || Number.isNaN(seconds)) return '尚未运行'
  const then = new Date(seconds * 1000)
  const diff = (nowTick.value - then.getTime()) / 1000
  const pad = (value) => String(value).padStart(2, '0')

  if (diff < 60) return '刚刚'
  if (diff < 3600) return `${Math.floor(diff / 60)} 分钟前`
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小时前`
  return `${then.getMonth() + 1}月${then.getDate()}日 ${pad(then.getHours())}:${pad(then.getMinutes())}`
}

let timer = null
function onVisibility() {
  if (document.visibilityState === 'visible' && !busy.value) refresh({ silent: true })
}

onMounted(() => {
  refresh()
  timer = setInterval(() => {
    if (document.visibilityState === 'visible' && !busy.value) refresh({ silent: true })
  }, 20000)
  document.addEventListener('visibilitychange', onVisibility)
})

onBeforeUnmount(() => {
  if (timer) clearInterval(timer)
  if (heartTimer) clearTimeout(heartTimer)
  document.removeEventListener('visibilitychange', onVisibility)
})
</script>

<template>
  <div class="app">
    <div class="shell">
      <header class="app-header reveal">
        <div class="brand-mark">
          <img :src="iconUrl" alt="" />
        </div>
        <div class="brand-text">
          <h1 class="brand-title">ADB Disabler</h1>
          <p class="brand-sub">ADB 控制台</p>
        </div>
        <div class="header-actions">
          <MiuixIconButton
            aria-label="刷新状态"
            :class="{ 'is-spinning': refreshing }"
            @click="refresh()"
          >
            <MiuixIcon :icon="Refresh" :size="20" />
          </MiuixIconButton>
          <MiuixIconButton
            :aria-label="theme === 'dark' ? '切换到浅色模式' : '切换到深色模式'"
            @click="toggleTheme"
          >
            <span class="theme-toggle-icon">
              <svg
                class="theme-sun"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.7"
                stroke-linecap="round"
                aria-hidden="true"
              >
                <circle cx="12" cy="12" r="4.1" />
                <path
                  d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.4 5.4l1.6 1.6M17 17l1.6 1.6M18.6 5.4 17 7M7 17l-1.6 1.6"
                />
              </svg>
              <svg
                class="theme-moon"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.7"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path d="M20.5 14.2A8.6 8.6 0 0 1 9.8 3.5a8.6 8.6 0 1 0 10.7 10.7Z" />
              </svg>
            </span>
          </MiuixIconButton>
        </div>
      </header>

      <MiuixCard v-if="isDemo" class="notice reveal">
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>浏览器预览</b>
            <span>未检测到模块管理器，当前显示模拟数据。</span>
          </div>
        </div>
      </MiuixCard>

      <MiuixCard v-if="needsGrant" class="notice notice--error reveal">
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>MMRL 授权未开启</b>
            <span>请在 MMRL 的模块设置中允许本模块使用「高级 KernelSU API」，然后重新打开 WebUI。</span>
          </div>
        </div>
      </MiuixCard>

      <MiuixCard v-if="fatal" class="notice notice--error reveal">
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>读取失败</b>
            <span>{{ fatal }}</span>
          </div>
        </div>
      </MiuixCard>

      <MiuixCard
        v-if="!isDemo && !needsGrant && status.boot === '1' && !status.resetprop"
        class="notice notice--error reveal"
      >
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>未找到 resetprop</b>
            <span>请确认当前管理器提供 resetprop，否则部分防护无法生效。</span>
          </div>
        </div>
      </MiuixCard>

      <MiuixCard
        v-if="!isDemo && !needsGrant && status.disabled === '1'"
        class="notice notice--error reveal"
      >
        <div class="notice__row">
          <MiuixIcon :icon="Info" :size="18" />
          <div class="notice__copy">
            <b>模块已停用</b>
            <span>service.sh 不会在开机时执行，请在管理器中重新启用模块。</span>
          </div>
        </div>
      </MiuixCard>

      <template v-if="!needsGrant">
      <MiuixCard class="hero reveal" :data-state="posture">
        <div class="hero__body">
          <div class="hero__badge">
            <MiuixIcon
              :icon="posture === 'ok' ? Lock : posture === 'unknown' ? Info : Unlock"
              :size="28"
            />
          </div>
          <div class="hero__copy">
            <span class="hero__eyebrow">
              <i class="live-dot"></i>
              {{ loading ? '正在读取' : 'SECURITY POSTURE' }}
            </span>
            <h2 class="hero__title">{{ headline }}</h2>
            <p class="hero__sub">{{ subline }}</p>
          </div>
          <div class="hero__ring">
            <svg viewBox="0 0 56 56" aria-hidden="true">
              <circle class="ring-track" cx="28" cy="28" r="23" />
              <circle
                class="ring-value"
                cx="28"
                cy="28"
                r="23"
                :style="{ strokeDasharray: RING, strokeDashoffset: ringOffset }"
              />
            </svg>
            <span class="hero__score">{{ sealedCount }}<em>/3</em></span>
          </div>
        </div>

        <div class="hero__leds">
          <div
            v-for="item in items"
            :key="item.key"
            class="led"
            :class="'is-' + item.state"
          >
            <span class="led__dot"></span>
            <span class="led__label">{{ item.short }}</span>
            <span class="led__value">{{ stateText(item.state) }}</span>
          </div>
        </div>

        <div class="hero__tape">BOOT-TIME ENFORCEMENT</div>
      </MiuixCard>

      <MiuixSmallTitle class="section-title">防护项</MiuixSmallTitle>
      <MiuixCard class="list-card reveal">
        <template v-for="(item, index) in items" :key="item.key">
          <MiuixDivider v-if="index" class="row-divider" />
          <MiuixSwitchPreference
            :model-value="isChecked(item)"
            :title="item.title"
            :summary="item.summary"
            :disabled="!!pending[item.key] || busy"
            @update:model-value="onToggle(item, $event)"
          >
            <template #start>
              <span class="row-icon" :class="'tone-' + item.tone">
                <MiuixIcon :icon="item.icon" :size="18" />
              </span>
            </template>
            <template #end>
              <span v-if="pending[item.key]" class="row-pending">处理中</span>
            </template>
          </MiuixSwitchPreference>
        </template>
      </MiuixCard>

      <MiuixSmallTitle class="section-title">操作</MiuixSmallTitle>
      <div class="button-stack reveal">
        <MiuixButton class="btn-xl btn-primary-xl" type="primary" :disabled="busy" @click="sealNow">
          <span class="btn-inner">
            <MiuixIcon :icon="sealing ? Refresh : Lock" :size="19" />
            <span>{{ sealing ? '正在启用…' : '立即启用' }}</span>
          </span>
        </MiuixButton>
      </div>

      <MiuixSmallTitle class="section-title">模块</MiuixSmallTitle>
      <MiuixCard class="list-card reveal">
        <MiuixArrowPreference
          title="运行日志"
          summary="最近 200 行运行记录"
          @click="openLog"
        >
          <template #start>
            <span class="row-icon tone-slate"><MiuixIcon :icon="Notes" :size="18" /></span>
          </template>
        </MiuixArrowPreference>
        <MiuixDivider class="row-divider" />
        <MiuixArrowPreference
          title="诊断信息"
          summary="属性、环境与设备细节"
          @click="openDiag"
        >
          <template #start>
            <span class="row-icon tone-slate"><MiuixIcon :icon="Tune" :size="18" /></span>
          </template>
        </MiuixArrowPreference>
      </MiuixCard>

      <footer class="footnote">
        <button class="sponsor-entry" type="button" @click="sponsorOpen = true">
          <MiuixIcon :icon="FavoritesFill" :size="16" />
          <span>赞助开发</span>
        </button>
        <p class="footnote__meta">ADB Disabler · GPL-3.0</p>
      </footer>
      </template>
    </div>

    <MiuixBottomSheet v-model="logSheet" title="运行日志">
      <template #end-action>
        <MiuixIconButton aria-label="刷新日志" @click="refreshLog">
          <MiuixIcon :icon="Refresh" :size="19" />
        </MiuixIconButton>
      </template>
      <div class="sheet-body">
        <p class="sheet-hint">最近 200 行 · 由 service.sh 与 WebUI 追加</p>
        <pre class="log-view">{{ logText }}</pre>
        <div class="sheet-actions">
          <MiuixButton class="sheet-btn" @click="copyLog">
            <span class="btn-inner">
              <MiuixIcon :icon="Copy" :size="17" />
              <span>复制</span>
            </span>
          </MiuixButton>
          <MiuixButton class="sheet-btn sheet-btn--danger" @click="askClearLog">
            <span class="btn-inner">
              <MiuixIcon :icon="Delete" :size="17" />
              <span>清空</span>
            </span>
          </MiuixButton>
        </div>
      </div>
    </MiuixBottomSheet>

    <MiuixBottomSheet v-model="diagSheet" title="诊断信息">
      <template #end-action>
        <MiuixIconButton aria-label="复制诊断信息" @click="copyDiag">
          <MiuixIcon :icon="Copy" :size="19" />
        </MiuixIconButton>
      </template>
      <div class="sheet-body">
        <dl class="diag">
          <div v-for="row in diagnostics" :key="row[0]" class="diag__row">
            <dt>{{ row[0] }}</dt>
            <dd>{{ row[1] || '—' }}</dd>
          </div>
        </dl>
      </div>
    </MiuixBottomSheet>

    <MiuixDialog v-model="sponsorOpen" title="赞助支持">
      <div class="sponsor-card">
        <div class="sponsor-head">
          <button
            class="sponsor-heart"
            :class="{ 'is-popping': heartPopping }"
            type="button"
            aria-label="感谢支持"
            @click="pulseHeart"
          >
            <svg class="heart-ring heart-ring--1" viewBox="0 0 24 24" aria-hidden="true">
              <path
                d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"
              />
            </svg>
            <svg class="heart-ring heart-ring--2" viewBox="0 0 24 24" aria-hidden="true">
              <path
                d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"
              />
            </svg>
            <MiuixIcon :icon="FavoritesFill" :size="24" />
          </button>
          <p class="sponsor-lead">
            如若 ADB Disabler 对您有所帮助<br />
            可否邀请开发者喝杯咖啡<br />
            这将会是我的荣幸
          </p>
        </div>
        <div class="sponsor-methods">
          <button
            v-for="method in sponsorMethods"
            :key="method.id"
            class="sponsor-tab"
            :class="{ 'is-active': sponsorMethod === method.id }"
            type="button"
            @click="sponsorMethod = method.id"
          >
            {{ method.label }}
          </button>
        </div>
        <div class="sponsor-qr">
          <img :src="currentSponsor.image" :alt="`${currentSponsor.label}赞赏码`" />
        </div>
        <p class="sponsor-hint">{{ currentSponsor.hint }}</p>
        <MiuixButton class="sponsor-close" @click="sponsorOpen = false">关闭</MiuixButton>
      </div>
    </MiuixDialog>

    <MiuixDialog
      v-model="confirmState.open"
      :title="confirmState.title"
      :summary="confirmState.summary"
    >
      <div class="dialog-actions">
        <MiuixButton class="dialog-btn" @click="confirmState.open = false">取消</MiuixButton>
        <MiuixButton
          class="dialog-btn"
          :class="{ 'danger-fill': confirmState.danger }"
          type="primary"
          @click="runConfirm"
        >
          {{ confirmState.confirmText }}
        </MiuixButton>
      </div>
    </MiuixDialog>

    <MiuixSnackbarHost />
  </div>
</template>
