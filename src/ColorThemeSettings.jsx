import { useEffect, useLayoutEffect, useState } from 'react'
import { Check, Palette, RotateCcw } from 'lucide-react'
import {
  applyColorTheme, COLOR_THEME_PRESETS, COLOR_THEME_STORAGE_KEY,
  colorThemeVariables, DEFAULT_COLOR_THEME, loadColorTheme,
  normalizeHexColor, saveColorTheme,
} from './color-themes.js'
import './ColorThemeSettings.css'

function currentSavedTheme() {
  try { return loadColorTheme(window.localStorage) } catch { return { ...DEFAULT_COLOR_THEME } }
}

export function useColorTheme() {
  const [theme, setTheme] = useState(currentSavedTheme)
  const [dark, setDark] = useState(() => window.matchMedia('(prefers-color-scheme: dark)').matches)
  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    const change = () => setDark(media.matches)
    media.addEventListener('change', change)
    const sync = (event) => {
      if (event.key === COLOR_THEME_STORAGE_KEY || event.key === null) setTheme(currentSavedTheme())
    }
    window.addEventListener('storage', sync)
    return () => {
      media.removeEventListener('change', change)
      window.removeEventListener('storage', sync)
    }
  }, [])
  useLayoutEffect(() => { applyColorTheme(document.documentElement, theme, dark) }, [theme, dark])
  return {
    theme, dark,
    save(value) { setTheme(saveColorTheme(window.localStorage, value)) },
    clear() {
      window.localStorage.removeItem(COLOR_THEME_STORAGE_KEY)
      setTheme({ ...DEFAULT_COLOR_THEME })
    },
  }
}

export default function ColorThemeSettings({ controller, language }) {
  const { theme, dark } = controller
  const english = language === 'en'
  const text = (zh, en) => english ? en : zh
  const [draft, setDraft] = useState(theme)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)
  const [editingCustom, setEditingCustom] = useState(false)
  useEffect(() => { setDraft(theme); setEditingCustom(false) }, [theme])
  const fields = [
    ['customPrimary', text('主色', 'Primary color')],
    ['customAccent', text('强调色', 'Accent color')],
    ['customSelectedDate', text('选中日期色', 'Selected date color')],
  ]
  const valid = fields.every(([key]) => normalizeHexColor(draft[key]))
  const commit = (value) => {
    try {
      controller.save(value)
      setError('')
      setSaved(true)
    } catch {
      setSaved(false)
      setError(text('无法保存主题，请检查颜色格式或本地存储权限。', 'Cannot save the theme. Check the color format or local storage access.'))
    }
  }
  return (
    <section className="panel settings-color-theme" aria-labelledby="color-theme-title">
      <div className="panel-title"><Palette size={18} /><h2 id="color-theme-title">{text('颜色主题', 'Color theme')}</h2></div>
      <p className="theme-description">{text('背景、卡片与控件协调换色；默认配色及 DDL 分类色保留。', 'Backgrounds, cards and controls change together. Default and DDL category colors stay unchanged.')}</p>
      <div className="theme-presets" role="group" aria-label={text('预设主题', 'Theme presets')}>
        {COLOR_THEME_PRESETS.map((preset) => (
          <button type="button" key={preset.id} aria-pressed={theme.preset === preset.id}
            className={theme.preset === preset.id ? 'theme-preset active' : 'theme-preset'}
            onClick={() => commit({ ...theme, preset: preset.id })}>
            <span className="theme-preset-dots" aria-hidden="true">
              {[preset.primary, preset.accent, preset.selectedDate].map((color, index) => <i key={index} style={{ backgroundColor: color }} />)}
            </span>
            <span>{english ? preset.nameEn : preset.nameZh}</span>
            {theme.preset === preset.id && <Check size={16} aria-hidden="true" />}
          </button>
        ))}
        <button type="button" className={theme.preset === 'custom' ? 'theme-preset active' : 'theme-preset'}
          aria-pressed={theme.preset === 'custom'} onClick={() => commit({ ...theme, preset: 'custom' })}>
          <Palette size={16} aria-hidden="true" />{text('自定义', 'Custom')}
          {theme.preset === 'custom' && <Check size={16} aria-hidden="true" />}
        </button>
      </div>
      <fieldset className="theme-custom-fields">
        <legend>{text('自定义配色', 'Custom colors')}</legend>
        {fields.map(([key, label]) => (
          <label key={key} className="theme-color-field">
            <span>{label}</span>
            <span className="theme-color-inputs">
              <input type="color" aria-label={label + text('取色器', ' picker')}
                value={normalizeHexColor(draft[key]) || DEFAULT_COLOR_THEME[key]}
                onChange={(event) => { setDraft({ ...draft, [key]: event.target.value }); setSaved(false); setEditingCustom(true) }} />
              <input type="text" value={draft[key]} spellCheck={false} autoComplete="off" maxLength={32}
                aria-label={label + ' HEX'} aria-invalid={!normalizeHexColor(draft[key])}
                aria-describedby="theme-color-hint"
                onChange={(event) => { setDraft({ ...draft, [key]: event.target.value }); setSaved(false); setEditingCustom(true) }}
                onKeyDown={(event) => {
                  if (event.key === 'Enter' && valid) { event.preventDefault(); commit({ ...draft, preset: 'custom' }) }
                }} />
            </span>
          </label>
        ))}
        <p id="theme-color-hint" className="theme-description">{text('输入 #RRGGBB；主色自动生成柔和背景，文字对比度自动调整。', 'Enter #RRGGBB. Your primary color creates soft backgrounds, with readable text contrast.')}</p>
      </fieldset>
      <div className="theme-preview" style={colorThemeVariables(editingCustom && valid ? { ...draft, preset: 'custom' } : theme, dark)}
        aria-label={text('完整主题预览', 'Full theme preview')}>
        <div className="theme-preview-toolbar"><strong>Where To Study</strong><span>{text('主题预览', 'Theme preview')}</span></div>
        <div className="theme-preview-card">
          <div className="theme-preview-heading"><strong>{text('教学日历', 'Teaching Calendar')}</strong><span className="theme-preview-selected">18</span></div>
          <div className="theme-preview-course"><i aria-hidden="true" /><div><strong>{text('今日课程', "Today's course")}</strong><small>08:00–09:35</small></div></div>
          <div className="theme-preview-controls"><span className="theme-preview-primary">{text('查询', 'Query')}</span><span className="theme-preview-accent">{text('已收藏', 'Saved')}</span></div>
        </div>
      </div>
      <div className="theme-actions">
        <button type="button" className="primary" disabled={!valid} onClick={() => commit({ ...draft, preset: 'custom' })}>{text('应用自定义配色', 'Apply custom colors')}</button>
        <button type="button" className="secondary" onClick={() => commit({ ...theme, preset: 'default' })}><RotateCcw size={16} />{text('恢复默认', 'Restore default')}</button>
      </div>
      {!valid && <p className="theme-error" role="alert">{text('请输入六位十六进制颜色，例如 #166B5D。', 'Enter a six-digit hexadecimal color, for example #166B5D.')}</p>}
      {error && <p className="theme-error" role="alert">{error}</p>}
      {saved && !error && <p className="theme-description" role="status">{text('主题已保存', 'Theme saved')}</p>}
    </section>
  )
}
