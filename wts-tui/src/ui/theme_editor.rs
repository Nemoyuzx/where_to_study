use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};
use ratatui::Frame;

use crate::color_theme::{color, rgb, ThemeEditor, PRESETS};
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, editor: &ThemeEditor, theme: &Theme) {
    frame.render_widget(
        Block::default().style(Style::default().bg(theme.background).fg(theme.text)),
        area,
    );
    let areas = Layout::vertical([Constraint::Min(0), Constraint::Length(3)]).split(area);
    let block = Block::default()
        .borders(Borders::ALL)
        .title("颜色主题 / Color Theme");
    let inner = block.inner(areas[0]);
    frame.render_widget(block, areas[0]);

    let mut lines = Vec::new();
    let labels = [
        "预设 / Preset",
        "主色 / Primary",
        "强调色 / Accent",
        "日期 / Selected Date",
    ];
    for (index, label) in labels.iter().enumerate() {
        let focused = editor.focus == index;
        lines.push(
            Line::from(format!("{} {label}", if focused { ">" } else { " " })).style(if focused {
                theme.strong_text()
            } else {
                theme.muted_text()
            }),
        );
        let value = if index == 0 {
            format!("← {} →", editor.selection.preset)
        } else {
            editor.drafts[index - 1].clone()
        };
        lines.push(Line::from(format!("  {value}")).style(if focused {
            theme.primary_selected()
        } else {
            theme.strong_text()
        }));
    }
    lines.push(Line::from(""));
    lines.push(Line::from("预览 / Preview"));
    lines.push(Line::from(vec![
        Span::styled(" Course 08:00 ", theme.primary_selected()),
        Span::raw(" "),
        Span::styled(
            " 12 ",
            Style::default()
                .fg(theme.on_selected_date)
                .bg(theme.selected_date),
        ),
        Span::raw(" "),
        Span::styled("Accent", theme.gold_text()),
    ]));
    lines.push(Line::from(""));
    for preset in PRESETS.iter() {
        lines.push(Line::from(vec![
            Span::raw(if editor.selection.preset == preset.id {
                "✓ "
            } else {
                "  "
            }),
            Span::styled("██", Style::default().fg(color(rgb(&preset.primary)))),
            Span::styled("██", Style::default().fg(color(rgb(&preset.accent)))),
            Span::styled("██", Style::default().fg(color(rgb(&preset.selected_date)))),
            Span::raw(format!(" {} / {}", preset.name_zh, preset.name_en)),
        ]));
    }
    let focus_line = editor.focus as u16 * 2 + 1;
    let scroll = focus_line.saturating_add(1).saturating_sub(inner.height);
    frame.render_widget(Paragraph::new(lines).scroll((scroll, 0)), inner);

    let compact = area.width < 60;
    let footer = vec![
        Line::from(editor.error.as_deref().unwrap_or(if compact {
            "Tab↑↓ 焦点 · ←→ 预设"
        } else {
            "Tab/↑↓ 焦点 Focus · ←/→ 预设 Preset · Ctrl+U 清空 Clear"
        }))
        .style(if editor.error.is_some() {
            theme.danger_text()
        } else {
            theme.muted_text()
        }),
        Line::from(if compact {
            "Enter 保存 · F2 默认"
        } else {
            "Enter 保存/Save · F2 恢复默认/Default · Esc 返回/Back"
        })
        .style(Style::default().add_modifier(Modifier::BOLD)),
        Line::from(if compact {
            "Esc 返回 · Ctrl+U 清空"
        } else {
            "F2 后按 Enter 保存；Esc 取消 / Enter confirms; Esc cancels"
        })
        .style(theme.muted_text()),
    ];
    frame.render_widget(Paragraph::new(footer), areas[1]);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::App;
    use crate::color_theme::ColorTheme;
    use ratatui::{backend::TestBackend, Terminal};

    #[test]
    fn theme_panel_renders_labels_swatches_and_actual_preview_colors() {
        let mut app = App::new(false);
        let config = ColorTheme {
            preset: "violet".into(),
            ..ColorTheme::default()
        };
        app.theme_editor = Some(ThemeEditor::new(&config));
        let theme = crate::current_theme(&app);
        let mut terminal = Terminal::new(TestBackend::new(100, 24)).unwrap();
        terminal
            .draw(|frame| crate::ui::draw(frame, &mut app, &theme))
            .unwrap();
        let cells = terminal.backend().buffer().content();
        let text: String = cells.iter().map(|cell| cell.symbol()).collect();
        for label in [
            "Color Theme",
            "Primary",
            "Accent",
            "Selected Date",
            "Preview",
            "Classic Teal",
            "Ocean Blue",
            "Iris Violet",
            "Warm Amber",
            "Rose",
        ] {
            assert!(text.contains(label), "missing {label}");
        }
        assert!(cells.iter().any(|cell| cell.symbol() == "C"
            && cell.bg == theme.primary_fill
            && cell.fg == theme.on_primary));
        assert!(cells.iter().any(|cell| cell.symbol() == "1"
            && cell.bg == theme.selected_date
            && cell.fg == theme.on_selected_date));
        assert!(cells
            .iter()
            .any(|cell| cell.symbol() == "█" && cell.fg == color(rgb("#D08A2E"))));
    }

    #[test]
    fn narrow_terminals_keep_the_active_field_visible_and_do_not_panic() {
        for (width, height) in [(1, 1), (12, 6), (24, 12), (40, 16), (80, 24)] {
            for focus in 0..4 {
                let mut app = App::new(true);
                let mut editor = ThemeEditor::new(&ColorTheme::default());
                editor.focus = focus;
                app.theme_editor = Some(editor);
                let theme = crate::current_theme(&app);
                let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
                terminal
                    .draw(|frame| crate::ui::draw(frame, &mut app, &theme))
                    .unwrap();
                if width >= 24 && focus == 3 {
                    let text: String = terminal
                        .backend()
                        .buffer()
                        .content()
                        .iter()
                        .map(|cell| cell.symbol())
                        .collect();
                    assert!(text.contains("#2563EB"));
                    assert!(text.contains("Esc"));
                }
            }
        }
    }
}
