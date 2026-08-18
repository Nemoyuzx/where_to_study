use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::App;
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, app: &mut App, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Length(44), Constraint::Min(20)])
        .split(area);

    // Left: filters
    let filter_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(5),
            Constraint::Min(6),
            Constraint::Length(4),
        ])
        .split(chunks[0]);

    // Campus selector
    let campus_items = [
        ListItem::new(format!(
            "{} 西土城",
            if app.campus_id == "01" { "●" } else { "○" }
        )),
        ListItem::new(format!(
            "{} 沙河",
            if app.campus_id == "04" { "●" } else { "○" }
        )),
    ];
    let campus_list = List::new(campus_items).block(
        Block::default()
            .borders(Borders::ALL)
            .title("校区（←→切换）"),
    );

    frame.render_widget(campus_list, filter_chunks[0]);

    // Buildings
    let building_items: Vec<ListItem> = if app.available_buildings.is_empty() {
        vec![ListItem::new("（获取空教室后显示教学楼）").style(theme.muted_text())]
    } else {
        app.available_buildings
            .iter()
            .map(|building| {
                let selected = app.selected_buildings.contains(building);
                ListItem::new(format!(
                    "{} {}{}",
                    if selected { "☑" } else { "☐" },
                    building,
                    if selected { " ✓" } else { "" }
                ))
                .style(if selected {
                    theme.primary_text()
                } else {
                    theme.muted_text()
                })
            })
            .collect()
    };
    let building_list = List::new(building_items).block(
        Block::default()
            .borders(Borders::ALL)
            .title("教学楼（空格选择）"),
    );

    frame.render_widget(building_list, filter_chunks[1]);

    // Slots summary
    let slots_text = if app.all_slots_selected {
        "全部节次".to_string()
    } else {
        let labels: Vec<String> = app
            .selected_slots
            .iter()
            .map(|slot| (slot + 1).to_string())
            .collect();
        format!("节次：{}", labels.join(","))
    };
    let slots_para = Paragraph::new(format!(
        "{slots_text}
[1-9/0] 切换节次 · [a] 全选 · [c] 清空"
    ))
    .block(Block::default().borders(Borders::ALL).title("节次筛选"))
    .wrap(Wrap { trim: false });

    frame.render_widget(slots_para, filter_chunks[2]);

    // Right: results
    let rooms = app.matching_rooms();
    let room_count = rooms.len();
    let mut items = vec![];
    if rooms.is_empty() {
        items.push(
            ListItem::new(if app.classrooms.is_some() {
                "没有匹配的空教室。"
            } else {
                "尚未获取空教室数据。请先登录并获取。"
            })
            .style(theme.muted_text()),
        );
    } else {
        let mut current_building = String::new();
        for room in rooms {
            if room.building != current_building {
                current_building = room.building.clone();
                items
                    .push(ListItem::new(format!("[{}]", room.building)).style(theme.strong_text()));
            }
            let size = room
                .size
                .map(|s| format!("{s}座"))
                .unwrap_or_else(|| "座位未知".to_string());
            let slots: Vec<String> = room
                .available_slots
                .iter()
                .map(|slot| (slot + 1).to_string())
                .collect();
            items.push(ListItem::new(format!(
                "  {} · {} · 空闲节次: {}",
                room.room,
                size,
                slots.join(",")
            )));
        }
    }
    let results_list = List::new(items).block(
        Block::default()
            .borders(Borders::ALL)
            .title(format!("空教室结果（{room_count} 间）")),
    );

    frame.render_widget(results_list, chunks[1]);
}
