import contract from '../contracts/v1/color-themes.json' with { type: 'json' }

export const COLOR_THEME_STORAGE_KEY = 'wts-color-theme-v1'
export const COLOR_THEME_PRESETS = Object.freeze(contract.presets)
export const DEFAULT_COLOR_THEME = Object.freeze({
  preset: 'default',
  customPrimary: '#166B5D',
  customAccent: '#E2BC62',
  customSelectedDate: '#2563EB',
})

export function normalizeHexColor(value) {
  if (typeof value !== 'string') return null
  const raw = value.trim().replace(/^#/, '')
  return /^[0-9a-f]{6}$/i.test(raw) ? '#' + raw.toUpperCase() : null
}

export function normalizeColorTheme(value) {
  const input = value && typeof value === 'object' ? value : {}
  return {
    preset: ['custom', ...COLOR_THEME_PRESETS.map((item) => item.id)].includes(input.preset)
      ? input.preset : 'default',
    customPrimary: normalizeHexColor(input.customPrimary) || DEFAULT_COLOR_THEME.customPrimary,
    customAccent: normalizeHexColor(input.customAccent) || DEFAULT_COLOR_THEME.customAccent,
    customSelectedDate: normalizeHexColor(input.customSelectedDate) || DEFAULT_COLOR_THEME.customSelectedDate,
  }
}

export function loadColorTheme(storage) {
  try {
    return normalizeColorTheme(JSON.parse(storage.getItem(COLOR_THEME_STORAGE_KEY)))
  } catch {
    return { ...DEFAULT_COLOR_THEME }
  }
}

export function saveColorTheme(storage, value) {
  // Validate edits before normalization: corrupt persisted values may recover,
  // but an invalid user edit must never silently replace a saved color.
  for (const key of ['customPrimary', 'customAccent', 'customSelectedDate']) {
    if (!normalizeHexColor(value[key])) throw new Error('invalid-color')
  }
  const theme = normalizeColorTheme(value)
  storage.setItem(COLOR_THEME_STORAGE_KEY, JSON.stringify(theme))
  return theme
}

export function rgbComponents(hex) {
  const normalized = normalizeHexColor(hex)
  if (!normalized) throw new Error('invalid-color')
  return [1, 3, 5].map((offset) => parseInt(normalized.slice(offset, offset + 2), 16))
}

function hexFromRGB(components) {
  return '#' + components.map((value) => Math.round(value).toString(16).padStart(2, '0')).join('').toUpperCase()
}

export function mixColor(color, target, amount) {
  const first = rgbComponents(color)
  const second = rgbComponents(target)
  return hexFromRGB(first.map((value, index) => value + (second[index] - value) * amount))
}

export function colorLuminance(hex) {
  const values = rgbComponents(hex).map((value) => {
    const component = value / 255
    return component <= 0.04045 ? component / 12.92 : ((component + 0.055) / 1.055) ** 2.4
  })
  return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
}

export function colorContrast(first, second) {
  const a = colorLuminance(first)
  const b = colorLuminance(second)
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

export function readableColor(seed, background, target) {
  const normalized = normalizeHexColor(seed)
  if (colorContrast(normalized, background) >= 4.5) return normalized
  for (let step = 1; step <= 50; step += 1) {
    const candidate = mixColor(normalized, target, step / 50)
    if (colorContrast(candidate, background) >= 4.5) return candidate
  }
  return target
}

export function colorThemeSeeds(settings) {
  const theme = normalizeColorTheme(settings)
  if (theme.preset === 'custom') {
    return { primary: theme.customPrimary, accent: theme.customAccent, selectedDate: theme.customSelectedDate }
  }
  return COLOR_THEME_PRESETS.find((item) => item.id === theme.preset)
}

export function resolvedColorTheme(settings, dark = false) {
  const seeds = colorThemeSeeds(settings)
  const surfaces = colorThemeSurfaces(settings, dark)
  const fill = readableColor(seeds.primary, '#FFFFFF', '#000000')
  const selected = readableColor(seeds.selectedDate, '#FFFFFF', '#000000')
  return {
    primaryFill: fill,
    primaryText: readableColor(seeds.primary, surfaces.worstSurface, dark ? '#FFFFFF' : '#000000'),
    accent: seeds.accent,
    accentText: readableColor(seeds.accent, surfaces.worstSurface, dark ? '#FFFFFF' : '#000000'),
    selectedDate: selected,
    selectedOutline: readableColor(seeds.selectedDate, surfaces.worstSurface, dark ? '#FFFFFF' : '#000000'),
    surfaces,
  }
}

export function colorThemeSurfaces(settings, dark = false) {
  const recipe = contract.surfaces[dark ? 'dark' : 'light']
  const seed = colorThemeSeeds(settings).primary
  const surfaces = Object.fromEntries(
    ['background', 'surface', 'elevated', 'surfaceVariant', 'border'].map((role) => (
      [role, mixColor(recipe[role].base, seed, recipe[role].primaryAmount)]
    )),
  )
  const candidates = ['background', 'surface', 'elevated', 'surfaceVariant'].map((key) => surfaces[key])
  const worstSurface = candidates.reduce((worst, value) => (
    (dark ? colorLuminance(value) > colorLuminance(worst) : colorLuminance(value) < colorLuminance(worst))
      ? value : worst
  ))
  return {
    ...surfaces, worstSurface,
    text: readableColor(recipe.text, worstSurface, dark ? '#FFFFFF' : '#000000'),
    secondaryText: readableColor(recipe.secondaryText, worstSurface, dark ? '#FFFFFF' : '#000000'),
  }
}

export function colorThemeVariables(settings, dark = false) {
  // No overrides for default: preserve the exact pre-existing CSS palette.
  if (normalizeColorTheme(settings).preset === 'default') return {}
  const theme = resolvedColorTheme(settings, dark)
  const { surfaces } = theme
  const surface = surfaces.surface
  const seed = colorThemeSeeds(settings).primary
  const tinted = (color, opacity) => mixColor(surface, color, opacity)
  const rgba = (color, opacity) => 'rgba(' + rgbComponents(color).join(', ') + ', ' + opacity + ')'
  const accentSurface = tinted(theme.accent, 0.20)
  const accentText = readableColor(theme.accentText, accentSurface, dark ? '#FFFFFF' : '#000000')
  const selectedSurface = tinted(seed, dark ? 0.20 : 0.14)
  const primaryText = readableColor(theme.primaryText, selectedSurface, dark ? '#FFFFFF' : '#000000')
  const selectedLane = tinted(theme.selectedOutline, 0.14)
  const inkBackdrops = [surfaces.worstSurface, selectedSurface, accentSurface, selectedLane]
  const worstInkBackdrop = inkBackdrops.reduce((worst, value) => (
    (dark ? colorLuminance(value) > colorLuminance(worst) : colorLuminance(value) < colorLuminance(worst))
      ? value : worst
  ))
  const text = readableColor(surfaces.text, worstInkBackdrop, dark ? '#FFFFFF' : '#000000')
  const secondaryText = readableColor(surfaces.secondaryText, worstInkBackdrop, dark ? '#FFFFFF' : '#000000')
  return {
    '--app-background': surfaces.background,
    '--background': surfaces.background,
    '--surface': surfaces.surface,
    '--surface-subtle': surfaces.elevated,
    '--surface-muted': surfaces.surfaceVariant,
    '--surface-cool': surfaces.surfaceVariant,
    '--segmented-selection': surfaces.elevated,
    '--text-primary': text,
    '--text-strong': text,
    '--text-heading': text,
    '--text-control': text,
    '--text-panel': text,
    '--text-secondary': secondaryText,
    '--text-secondary-strong': secondaryText,
    '--text-muted': secondaryText,
    '--text-soft': secondaryText,
    '--text-disabled': secondaryText,
    '--border': surfaces.border,
    '--border-subtle': mixColor(surface, surfaces.border, 0.65),
    '--divider': mixColor(surface, surfaces.border, 0.65),
    '--input-border': surfaces.border,
    '--slot-text': text,
    '--status-text': secondaryText,
    '--eyebrow-text': secondaryText,
    '--secondary-alt': secondaryText,
    '--control-text-blue': text,
    '--empty-surface': surfaces.surfaceVariant,
    '--empty-border': surfaces.border,
    '--empty-text': secondaryText,
    '--switch-track': surfaces.surfaceVariant,
    '--switch-border': surfaces.border,
    '--mobile-nav-background': rgba(surfaces.elevated, 0.96),
    '--primary': theme.primaryFill,
    '--primary-rgb': rgbComponents(theme.primaryFill).join(' '),
    '--primary-fill': theme.primaryFill,
    '--on-primary-muted': '#FFFFFF',
    '--primary-strong': theme.primaryFill,
    '--primary-focus': primaryText,
    '--primary-pressed': mixColor(theme.primaryFill, '#000000', 0.10),
    '--primary-text': primaryText,
    '--primary-text-strong': primaryText,
    '--primary-surface': tinted(seed, 0.10),
    '--primary-surface-soft': tinted(seed, 0.06),
    '--primary-surface-selected': tinted(seed, dark ? 0.16 : 0.10),
    '--primary-surface-selected-strong': selectedSurface,
    '--primary-surface-lane': tinted(seed, 0.03),
    '--primary-surface-calendar': tinted(seed, 0.06),
    '--primary-surface-holiday': tinted(seed, 0.04),
    '--primary-surface-holiday-badge': tinted(seed, 0.12),
    '--primary-border': tinted(theme.primaryText, 0.40),
    '--primary-border-soft': tinted(theme.primaryText, 0.30),
    '--primary-outline': theme.primaryText,
    '--selected-date-fill': theme.selectedDate,
    '--selected-date-lane': selectedLane,
    '--selected-date-outline': theme.selectedOutline,
    '--selected-date-text': '#FFFFFF',
    '--gold': theme.accent,
    '--gold-surface': accentSurface,
    '--gold-surface-soft': tinted(theme.accent, 0.10),
    '--gold-surface-calendar': tinted(theme.accent, 0.06),
    '--gold-text': accentText,
    '--gold-text-strong': accentText,
    '--gold-text-muted': accentText,
    '--gold-outline': theme.accentText,
    '--focus-ring': rgba(theme.primaryText, 0.28),
    '--mobile-active-start': rgba(seed, 0.10),
    '--mobile-active-end': rgba(seed, 0.16),
    '--mobile-active-border': rgba(seed, 0.16),
    '--mobile-active-shadow': '0 8px 20px ' + rgba(theme.primaryFill, 0.12),
  }
}

// Year cells use an explicit composite background so the computed ink matches
// the actual paint even when the year grid is transparent over the page canvas.
export function colorThemeHeatmap(palette, opacity) {
  const amount = Number.isFinite(opacity) ? Math.max(0, Math.min(1, opacity)) : 0
  const background = mixColor(palette.surfaces.background, palette.primaryFill, amount)
  const target = colorContrast('#000000', background) >= colorContrast('#FFFFFF', background)
    ? '#000000' : '#FFFFFF'
  return { background, text: readableColor(palette.surfaces.text, background, target) }
}

const THEME_VARIABLE_KEYS = Object.keys(colorThemeVariables({ preset: 'ocean' }))

export function applyColorTheme(root, settings, dark = false) {
  for (const name of THEME_VARIABLE_KEYS) root.style.removeProperty(name)
  for (const [name, value] of Object.entries(colorThemeVariables(settings, dark))) {
    root.style.setProperty(name, value)
  }
  root.dataset.colorTheme = normalizeColorTheme(settings).preset
}
