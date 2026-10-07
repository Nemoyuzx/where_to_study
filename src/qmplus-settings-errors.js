import {uiText} from './ui-text.js'

const fallback = 'QMplus 安全设置未能保存，请重试。'
// Only exact native errors select existing static catalog keys. The two native
// prerequisites use existing action prompts because their error text has no key.
const fixedErrors = new Map([
  ['QMplus 网页会话需要清理，请重新启动应用。', 'QMplus 网页会话需要清理，请重新启动应用。'],
  ['QMplus 尚未启用。', '启用 QMplus'],
  ['请先保存 QMplus 账号和密码。', '安全保存 QMplus 登录资料'],
  ['无法读取 QMplus 安全存储。', '无法读取 QMplus 安全存储。'],
])

export function qmplusSettingsErrorKey(failure) {
  try {
    const message = typeof failure === 'string' ? failure
      : failure && typeof failure === 'object' ? Object.getOwnPropertyDescriptor(failure, 'message')?.value : undefined
    return fixedErrors.get(message) || fallback
  } catch {
    return fallback
  }
}

export function qmplusSettingsErrorText(language, failure) {
  return uiText(language, qmplusSettingsErrorKey(failure))
}
