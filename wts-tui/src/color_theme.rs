//! Local-only color preferences. The embedded shared contract owns all preset seeds.
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    LazyLock,
};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::style::Color;
use serde::{Deserialize, Serialize};

use crate::theme::{Theme, DARK, LIGHT};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Preset {
    pub id: String,
    pub name_zh: String,
    pub name_en: String,
    pub primary: String,
    pub accent: String,
    pub selected_date: String,
}

#[derive(Deserialize)]
struct Contract {
    presets: Vec<Preset>,
}

pub static PRESETS: LazyLock<Vec<Preset>> = LazyLock::new(|| {
    serde_json::from_str::<Contract>(include_str!("../../contracts/v1/color-themes.json"))
        .expect("valid bundled color theme contract")
        .presets
});
pub const IDS: [&str; 6] = ["default", "ocean", "violet", "amber", "rose", "custom"];
static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ColorTheme {
    pub preset: String,
    pub primary: String,
    pub accent: String,
    pub selected_date: String,
}

impl Default for ColorTheme {
    fn default() -> Self {
        Self {
            preset: "default".into(),
            primary: PRESETS[0].primary.clone(),
            accent: PRESETS[0].accent.clone(),
            selected_date: PRESETS[0].selected_date.clone(),
        }
    }
}

impl ColorTheme {
    pub fn decode(text: &str) -> Self {
        let value: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
        let defaults = Self::default();
        let field = |name: &str, fallback: String| {
            value
                .get(name)
                .and_then(|v| v.as_str())
                .and_then(normalize_hex)
                .unwrap_or(fallback)
        };
        Self {
            preset: value
                .get("preset")
                .and_then(|v| v.as_str())
                .filter(|id| IDS.contains(id))
                .unwrap_or("default")
                .to_owned(),
            primary: field("primary", defaults.primary),
            accent: field("accent", defaults.accent),
            selected_date: field("selectedDate", defaults.selected_date),
        }
    }

    pub fn seeds(&self) -> [&str; 3] {
        if self.preset == "custom" {
            return [&self.primary, &self.accent, &self.selected_date];
        }
        let preset = PRESETS
            .iter()
            .find(|p| p.id == self.preset)
            .unwrap_or(&PRESETS[0]);
        [&preset.primary, &preset.accent, &preset.selected_date]
    }

    pub fn palette(&self, dark: bool) -> Theme {
        let mut palette = if dark { DARK } else { LIGHT };
        if self.preset == "default" || !IDS.contains(&self.preset.as_str()) {
            return palette;
        }
        let seeds = self.seeds().map(rgb);
        palette.primary_fill = color(fill(seeds[0]));
        palette.primary = color(readable(seeds[0], if dark { [40; 3] } else { [255; 3] }));
        palette.primary = color(readable(
            channels(palette.primary),
            channels(palette.background),
        ));
        palette.on_primary = color([255; 3]);
        palette.selected_date = color(fill(seeds[2]));
        palette.on_selected_date = color([255; 3]);
        palette.primary_soft = color(blend(
            channels(palette.surface),
            seeds[0],
            if dark { 0.18 } else { 0.1 },
        ));
        palette.gold = color(readable(seeds[1], channels(palette.background)));
        palette.gold_soft = color(blend(channels(palette.surface), seeds[1], 0.2));
        palette.focus = palette.primary;
        palette
    }
}

pub fn normalize_hex(text: &str) -> Option<String> {
    let digits = text.trim().strip_prefix('#').unwrap_or(text.trim());
    (digits.len() == 6 && digits.bytes().all(|ch| ch.is_ascii_hexdigit()))
        .then(|| format!("#{}", digits.to_ascii_uppercase()))
}

pub fn rgb(hex: &str) -> [u8; 3] {
    let normalized = normalize_hex(hex).unwrap_or_else(|| "#166B5D".into());
    [1, 3, 5].map(|offset| u8::from_str_radix(&normalized[offset..offset + 2], 16).unwrap())
}

pub fn color(rgb: [u8; 3]) -> Color {
    Color::Rgb(rgb[0], rgb[1], rgb[2])
}

pub fn channels(color: Color) -> [u8; 3] {
    match color {
        Color::Rgb(r, g, b) => [r, g, b],
        Color::White => [255; 3],
        _ => [0; 3],
    }
}

pub fn blend(from: [u8; 3], to: [u8; 3], amount: f64) -> [u8; 3] {
    [0, 1, 2].map(|i| {
        (from[i] as f64 + (to[i] as f64 - from[i] as f64) * amount.clamp(0.0, 1.0)).round() as u8
    })
}

pub fn contrast(a: [u8; 3], b: [u8; 3]) -> f64 {
    fn luminance(rgb: [u8; 3]) -> f64 {
        let c = rgb.map(|v| {
            let c = v as f64 / 255.0;
            if c <= 0.04045 {
                c / 12.92
            } else {
                ((c + 0.055) / 1.055).powf(2.4)
            }
        });
        0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }
    let (a, b) = (luminance(a), luminance(b));
    (a.max(b) + 0.05) / (a.min(b) + 0.05)
}

pub fn readable(seed: [u8; 3], background: [u8; 3]) -> [u8; 3] {
    let target = if contrast([0; 3], background) >= contrast([255; 3], background) {
        [0; 3]
    } else {
        [255; 3]
    };
    (0..=50)
        .map(|step| blend(seed, target, step as f64 * 0.02))
        .find(|candidate| contrast(*candidate, background) >= 4.5)
        .unwrap_or(target)
}

pub fn fill(seed: [u8; 3]) -> [u8; 3] {
    readable(seed, [255; 3])
}

pub fn config_path() -> Option<PathBuf> {
    crate::file_credentials::default_config_root().map(|root| {
        root.join("where-to-study")
            .join("wts-tui")
            .join("theme.json")
    })
}

pub fn load(path: &Path) -> io::Result<ColorTheme> {
    match fs::read_to_string(path) {
        Ok(text) => Ok(ColorTheme::decode(&text)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(ColorTheme::default()),
        Err(error) => Err(error),
    }
}

pub fn save(path: &Path, selection: &ColorTheme) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("missing theme directory"))?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".theme.{}.{}.tmp",
        std::process::id(),
        TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temporary)?;
        file.write_all(&serde_json::to_vec_pretty(selection)?)?;
        file.sync_all()?;
        drop(file);
        // rename atomically replaces the existing file on Unix. On Windows the
        // existing destination is replaced by std::fs::rename as well.
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

#[derive(Debug)]
pub struct ThemeEditor {
    pub selection: ColorTheme,
    pub drafts: [String; 3],
    pub focus: usize,
    pub error: Option<String>,
}

pub enum EditorAction {
    None,
    Cancel,
    Save(ColorTheme),
}

impl ThemeEditor {
    pub fn new(selection: &ColorTheme) -> Self {
        Self {
            selection: selection.clone(),
            drafts: [
                selection.primary.clone(),
                selection.accent.clone(),
                selection.selected_date.clone(),
            ],
            focus: 0,
            error: None,
        }
    }

    fn reset_drafts(&mut self) {
        self.drafts = [
            self.selection.primary.clone(),
            self.selection.accent.clone(),
            self.selection.selected_date.clone(),
        ];
        self.error = None;
    }

    fn accept_drafts(&mut self) -> bool {
        let normalized = self.drafts.each_ref().map(|text| normalize_hex(text));
        if let [Some(primary), Some(accent), Some(selected_date)] = normalized {
            self.selection.primary = primary;
            self.selection.accent = accent;
            self.selection.selected_date = selected_date;
            self.error = None;
            true
        } else {
            self.error = Some("请输入六位 RGB / Enter six HEX digits: #166B5D".into());
            false
        }
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> EditorAction {
        match key.code {
            KeyCode::Esc => return EditorAction::Cancel,
            KeyCode::Tab | KeyCode::Down => self.focus = (self.focus + 1) % 4,
            KeyCode::BackTab | KeyCode::Up => self.focus = (self.focus + 3) % 4,
            KeyCode::Left | KeyCode::Right if self.focus == 0 => {
                let index = IDS
                    .iter()
                    .position(|id| *id == self.selection.preset)
                    .unwrap_or(0);
                let delta = if key.code == KeyCode::Right {
                    1
                } else {
                    IDS.len() - 1
                };
                self.selection.preset = IDS[(index + delta) % IDS.len()].into();
                self.reset_drafts();
            }
            KeyCode::F(2) => {
                self.selection.preset = "default".into();
                self.reset_drafts();
                self.focus = 0;
            }
            KeyCode::Enter => {
                if self.accept_drafts() {
                    return EditorAction::Save(self.selection.clone());
                }
            }
            KeyCode::Backspace if self.focus > 0 => {
                self.drafts[self.focus - 1].pop();
                if self.accept_drafts() {
                    self.selection.preset = "custom".into();
                }
            }
            KeyCode::Char('u')
                if self.focus > 0 && key.modifiers.contains(KeyModifiers::CONTROL) =>
            {
                self.drafts[self.focus - 1].clear();
                self.accept_drafts();
            }
            KeyCode::Char(ch)
                if self.focus > 0 && !key.modifiers.contains(KeyModifiers::CONTROL) =>
            {
                if self.drafts[self.focus - 1].chars().count() < 32 {
                    self.drafts[self.focus - 1].push(ch);
                    if self.accept_drafts() {
                        self.selection.preset = "custom".into();
                    }
                }
            }
            _ => {}
        }
        EditorAction::None
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub struct TestDirectory(pub PathBuf);
    impl TestDirectory {
        pub fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "wts-theme-test-{}-{}",
                std::process::id(),
                TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
        pub fn path(&self) -> PathBuf {
            self.0.join("theme.json")
        }
    }
    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn strict_hex_and_corrupt_fields_recover_independently() {
        assert_eq!(normalize_hex(" #aB01ff ").as_deref(), Some("#AB01FF"));
        assert_eq!(normalize_hex("001122").as_deref(), Some("#001122"));
        for invalid in [
            "",
            "#FFF",
            "#AABBCCDD",
            "#12GG00",
            "rgb(0,0,0)",
            "##112233",
            "123 45",
            "1234567",
            "１２３４５６",
        ] {
            assert_eq!(normalize_hex(invalid), None);
        }
        let config = ColorTheme::decode(
            r##"{"preset":"unknown","primary":"bad","accent":"aabbcc","selectedDate":12}"##,
        );
        assert_eq!(config.preset, "default");
        assert_eq!(config.primary, "#166B5D");
        assert_eq!(config.accent, "#AABBCC");
        assert_eq!(config.selected_date, "#2563EB");
        for invalid in ["null", "[]", "{", "42", "\"custom\""] {
            assert_eq!(ColorTheme::decode(invalid), ColorTheme::default());
        }
    }

    #[test]
    fn shared_presets_and_default_palette_parity() {
        assert_eq!(
            PRESETS.iter().map(|p| p.id.as_str()).collect::<Vec<_>>(),
            IDS[..5]
        );
        assert_eq!(ColorTheme::default().palette(false), LIGHT);
        assert_eq!(ColorTheme::default().palette(true), DARK);
        assert_eq!(LIGHT.selected_date, LIGHT.primary);
        assert_eq!(DARK.selected_date, DARK.primary);
        assert_eq!(PRESETS[1].primary, "#1565C0");
        assert_eq!(PRESETS[2].selected_date, "#00796B");
    }

    #[test]
    fn colors_are_accessible_and_semantic_colors_do_not_change() {
        assert_eq!(contrast([0; 3], [255; 3]), 21.0);
        assert_eq!(fill([255; 3]), [117; 3]);
        assert!(contrast([122; 3], [255; 3]) < 4.5);
        let colors = [
            "#FFFFFF", "#FFFFEE", "#000000", "#000001", "#777777", "#00FF00",
        ];
        for preset in IDS {
            for value in colors {
                let config = ColorTheme {
                    preset: preset.into(),
                    primary: value.into(),
                    accent: value.into(),
                    selected_date: value.into(),
                };
                for dark in [false, true] {
                    let palette = config.palette(dark);
                    let original = if dark { DARK } else { LIGHT };
                    assert_eq!(palette.danger, original.danger);
                    assert_eq!(palette.event, original.event);
                    assert_eq!(palette.workday, original.workday);
                    assert_eq!(palette.background, original.background);
                    if preset != "default" {
                        assert!(
                            contrast(channels(palette.primary_fill), channels(palette.on_primary))
                                >= 4.5
                        );
                        assert!(
                            contrast(
                                channels(palette.selected_date),
                                channels(palette.on_selected_date)
                            ) >= 4.5
                        );
                        assert!(
                            contrast(channels(palette.primary), channels(palette.background))
                                >= 4.5
                        );
                        assert!(
                            contrast(channels(palette.gold), channels(palette.background)) >= 4.5
                        );
                        if dark {
                            assert!(contrast(channels(palette.primary), [40; 3]) >= 4.5);
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn persistence_roundtrip_replacement_and_corrupt_file() {
        let directory = TestDirectory::new();
        let path = directory.path();
        assert_eq!(load(&path).unwrap(), ColorTheme::default());
        let mut custom = ColorTheme {
            preset: "custom".into(),
            primary: "#123456".into(),
            accent: "#ABCDEF".into(),
            selected_date: "#336699".into(),
        };
        save(&path, &custom).unwrap();
        assert_eq!(load(&path).unwrap(), custom);
        custom.preset = "rose".into();
        save(&path, &custom).unwrap();
        assert_eq!(load(&path).unwrap(), custom);
        custom.preset = "default".into();
        save(&path, &custom).unwrap();
        assert_eq!(load(&path).unwrap().primary, "#123456");
        fs::write(&path, "{broken").unwrap();
        assert_eq!(load(&path).unwrap(), ColorTheme::default());
        assert_eq!(fs::read_dir(&directory.0).unwrap().count(), 1);
    }

    #[test]
    fn invalid_edits_keep_last_valid_preview_and_cannot_save() {
        let mut editor = ThemeEditor::new(&ColorTheme::default());
        editor.focus = 1;
        editor.handle_key(KeyEvent::new(KeyCode::Char('u'), KeyModifiers::CONTROL));
        for ch in "#FFF".chars() {
            editor.handle_key(KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE));
        }
        assert!(editor.error.is_some());
        assert_eq!(editor.selection, ColorTheme::default());
        assert!(matches!(
            editor.handle_key(KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE)),
            EditorAction::None
        ));
        for ch in "FFF".chars() {
            editor.handle_key(KeyEvent::new(KeyCode::Char(ch), KeyModifiers::NONE));
        }
        assert!(editor.error.is_none());
        assert_eq!(editor.selection.primary, "#FFFFFF");
        assert_eq!(editor.selection.preset, "custom");
        editor.handle_key(KeyEvent::new(KeyCode::F(2), KeyModifiers::NONE));
        assert_eq!(editor.selection.preset, "default");
        assert_eq!(editor.selection.primary, "#FFFFFF");
    }
}
