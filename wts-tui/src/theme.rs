use ratatui::style::{Color, Modifier, Style};

/// Application colour palette (mirrors the desktop app's green/gold scheme).
pub struct Theme {
    pub background: Color,
    pub primary: Color,
    pub text: Color,
    pub text_muted: Color,
    pub danger: Color,
    #[allow(dead_code)] // reserved for future detail styling
    pub surface: Color,
    #[allow(dead_code)]
    pub primary_soft: Color,
    pub gold: Color,
    #[allow(dead_code)]
    pub gold_soft: Color,
    #[allow(dead_code)]
    pub border: Color,
    #[allow(dead_code)]
    pub focus: Color,
}

pub const LIGHT: Theme = Theme {
    background: Color::Rgb(245, 246, 243),
    surface: Color::Rgb(255, 255, 255),
    primary: Color::Rgb(22, 107, 93),
    primary_soft: Color::Rgb(232, 244, 240),
    gold: Color::Rgb(226, 188, 98),
    gold_soft: Color::Rgb(255, 241, 204),
    text: Color::Rgb(23, 32, 27),
    text_muted: Color::Rgb(104, 115, 109),
    border: Color::Rgb(223, 228, 223),
    danger: Color::Rgb(227, 63, 63),
    focus: Color::Rgb(46, 125, 111),
};

pub const DARK: Theme = Theme {
    background: Color::Rgb(16, 20, 18),
    surface: Color::Rgb(26, 32, 29),
    primary: Color::Rgb(36, 125, 107),
    primary_soft: Color::Rgb(25, 54, 47),
    gold: Color::Rgb(226, 188, 98),
    gold_soft: Color::Rgb(59, 50, 27),
    text: Color::Rgb(237, 243, 239),
    text_muted: Color::Rgb(170, 182, 176),
    border: Color::Rgb(56, 67, 61),
    danger: Color::Rgb(255, 138, 128),
    focus: Color::Rgb(101, 198, 176),
};

impl Theme {
    pub fn primary_text(&self) -> Style {
        Style::default().fg(self.primary)
    }

    pub fn muted_text(&self) -> Style {
        Style::default().fg(self.text_muted)
    }

    pub fn strong_text(&self) -> Style {
        Style::default().fg(self.text).add_modifier(Modifier::BOLD)
    }

    pub fn danger_text(&self) -> Style {
        Style::default()
            .fg(self.danger)
            .add_modifier(Modifier::BOLD)
    }

    pub fn gold_text(&self) -> Style {
        Style::default().fg(self.gold).add_modifier(Modifier::BOLD)
    }
}

/// Detect whether the terminal requests a dark colour scheme.
/// Override with WTS_TUI_THEME=light|dark.
pub fn prefers_dark() -> bool {
    match std::env::var("WTS_TUI_THEME").as_deref() {
        Ok("dark") => return true,
        Ok("light") => return false,
        _ => {}
    }
    std::env::var("COLORFGBG")
        .ok()
        .and_then(|value| value.rsplit(';').next().map(str::to_string))
        .map(|background| background.starts_with('0') || background == "0")
        .unwrap_or(false)
}
