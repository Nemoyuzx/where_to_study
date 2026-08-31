use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph, Tabs, Wrap};
use ratatui::Frame;

use crate::app::{App, QuerySection};
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, app: &mut App, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(7),
        ])
        .split(area);

    let selected = match app.query_section {
        QuerySection::Shuttle => 0,
        QuerySection::Events => 1,
    };
    let tabs = Tabs::new(["班车查询", "重要事件查询"])
        .select(selected)
        .highlight_style(
            Style::default()
                .fg(theme.background)
                .bg(theme.primary)
                .add_modifier(Modifier::BOLD),
        )
        .divider("  ")
        .block(Block::default().borders(Borders::ALL).title("查询"));
    frame.render_widget(tabs, chunks[0]);

    match app.query_section {
        QuerySection::Shuttle => draw_shuttle(frame, &chunks, app, theme),
        QuerySection::Events => draw_events(frame, &chunks, app, theme),
    }
}

fn draw_shuttle(frame: &mut Frame, chunks: &[Rect], app: &App, theme: &Theme) {
    let summary = match app.shuttle.as_ref() {
        Some(response) => {
            let today = where_to_study_lib::public_queries::shuttle_today(response);
            let next = today.next_departure.as_deref().unwrap_or("没有待发班次");
            format!("{} · {} · {}", today.date, today.status, next)
        }
        None if app.loading => "正在后台获取班车状态与当前生效时刻表…".to_string(),
        None => "尚未加载班车数据，按 r 重试。".to_string(),
    };
    frame.render_widget(
        Paragraph::new(summary)
            .style(theme.strong_text())
            .block(Block::default().borders(Borders::ALL).title("今日状态")),
        chunks[1],
    );

    let mut lines = Vec::new();
    if let Some(response) = app.shuttle.as_ref() {
        let today = where_to_study_lib::public_queries::shuttle_today(response);
        if let Some(title) = today.notice_title {
            lines.push(Line::from(Span::styled(
                format!("生效通知：{title}"),
                theme.strong_text(),
            )));
        }
        for route in &today.routes {
            lines.push(Line::from(Span::styled(
                format!("{} → {} · {}", route.from, route.to, route.period_label),
                theme.primary_text(),
            )));
            if route.departures.is_empty() {
                lines.push(Line::from("  今日无发车安排"));
            }
            for departure in &route.departures {
                let marker = if departure.next {
                    "▶ 下一班"
                } else if departure.departed {
                    "  已发车"
                } else {
                    "  待发车"
                };
                lines.push(Line::from(format!(
                    "  {}  {}×{}  {marker}",
                    departure.time, departure.vehicle, departure.count
                )));
            }
        }
        if today.routes.is_empty() {
            lines.push(Line::from("当前没有处于生效日期范围内的已解析时刻表。"));
        }
        if !today.stops.is_empty() {
            lines.push(Line::from(Span::styled("发车地点", theme.strong_text())));
            for stop in &today.stops {
                lines.push(Line::from(format!("  {}：{}", stop.campus, stop.location)));
            }
        }
        for note in &today.notes {
            lines.push(Line::from(format!("提示：{note}")));
        }
    }
    frame.render_widget(
        Paragraph::new(lines)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title("当前生效时刻表（↑↓ / PgUp PgDn 滚动）"),
            )
            .scroll((app.query_scroll.min(u16::MAX as usize) as u16, 0))
            .wrap(Wrap { trim: false }),
        chunks[2],
    );

    let source = app.shuttle.as_ref().map_or_else(
        || "第三方来源：where-to-study.cn · 学校班车公开通知".to_string(),
        |response| {
            format!(
                "服务状态：{}{}\n第三方来源：{} · {}\n生成于：{}\n显示数据仅供参考，请以学校实际通知为准。",
                response.status,
                if response.status == "stale" {
                    "（缓存）"
                } else {
                    ""
                },
                response.source.name,
                response.source.page_url,
                response.generated_at
            )
        },
    );
    frame.render_widget(
        Paragraph::new(source)
            .style(theme.muted_text())
            .block(Block::default().borders(Borders::ALL).title("来源声明"))
            .wrap(Wrap { trim: false }),
        chunks[3],
    );
}

fn draw_events(frame: &mut Frame, chunks: &[Rect], app: &App, theme: &Theme) {
    let source_label = match app.query_source {
        where_to_study_lib::public_queries::ImportantEventSourceFilter::All => "全部",
        where_to_study_lib::public_queries::ImportantEventSourceFilter::Public => "公开",
        where_to_study_lib::public_queries::ImportantEventSourceFilter::School => "校内",
    };
    let search = if app.query_search_editing {
        format!("输入中：{}█", app.query_search)
    } else if app.query_search.is_empty() {
        "未设置（按 / 输入）".to_string()
    } else {
        app.query_search.clone()
    };
    let filters = format!(
        "搜索 {search} · 类型 {} · 分类 {} · 来源 {source_label} · 已结束 {} · 仅收藏 {}",
        app.query_event_type.as_deref().unwrap_or("全部"),
        app.query_category.as_deref().unwrap_or("全部"),
        if app.query_include_ended {
            "显示"
        } else {
            "隐藏"
        },
        if app.query_favorites_only {
            "是"
        } else {
            "否"
        },
    );
    frame.render_widget(
        Paragraph::new(filters)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title("/ 搜索 · x 清空 · t 类型 · c 真实分类 · p 来源 · e 已结束 · v 仅收藏"),
            )
            .wrap(Wrap { trim: false }),
        chunks[1],
    );

    let visible = app.visible_query_events();
    let take = chunks[2].height.saturating_sub(2) as usize;
    let lines: Vec<Line> = visible
        .iter()
        .enumerate()
        .skip(app.query_scroll)
        .take(take.max(1))
        .map(|(index, item)| {
            let selected = index == app.query_event_cursor;
            let favorite = if app.is_favorite(item) { "★" } else { "☆" };
            let source = if item.source_type == "school_notice" {
                "校内"
            } else {
                "公开"
            };
            let deadline = item.primary_deadline.replace('T', " ");
            let deadline = deadline.get(..16).unwrap_or(&deadline);
            let content = format!(
                "{} {favorite} {deadline} [{source}/{}] {}",
                if selected { "▶" } else { " " },
                event_type_label(&item.event_type),
                item.name
            );
            if selected {
                Line::from(content).style(
                    Style::default()
                        .fg(theme.background)
                        .bg(theme.primary)
                        .add_modifier(Modifier::BOLD),
                )
            } else {
                Line::from(content)
            }
        })
        .collect();
    let title = if app.important_events.is_none() && app.favorite_events.is_empty() {
        "重要事件（后台加载中；r 重试）".to_string()
    } else {
        format!(
            "重要事件 {} 项 · DDL 升序（↑↓ / PgUp PgDn · f 收藏）",
            visible.len()
        )
    };
    frame.render_widget(
        Paragraph::new(if lines.is_empty() {
            vec![Line::from("没有符合当前筛选条件的事件。")]
        } else {
            lines
        })
        .block(Block::default().borders(Borders::ALL).title(title)),
        chunks[2],
    );

    let detail = app.selected_query_event().map_or_else(
        || {
            let source = app
                .important_events
                .as_ref()
                .map(|response| response.source.as_str())
                .unwrap_or("本地收藏快照");
            format!(
                "第三方来源：{source}\n收藏保存在本地，即使远程条目消失仍可查看。\n显示数据仅供参考，请以实际情况为准。"
            )
        },
        |item| {
            format!(
                "{} · {}\n分类：{}\n主办/来源：{}\n{}\nfavorite_key：{}",
                item.deadline_label.as_deref().unwrap_or("DDL"),
                item.primary_deadline,
                if item.categories.is_empty() {
                    "未分类".to_string()
                } else {
                    item.categories.join(" / ")
                },
                item.organizer
                    .as_deref()
                    .or(item.source_name.as_deref())
                    .unwrap_or("未标注"),
                item.description
                    .as_deref()
                    .or(item.notes.as_deref())
                    .or(item.official_url.as_deref())
                    .unwrap_or("无补充说明"),
                where_to_study_lib::public_queries::favorite_key(&item)
            )
        },
    );
    frame.render_widget(
        Paragraph::new(detail)
            .style(theme.muted_text())
            .block(Block::default().borders(Borders::ALL).title("详情与来源"))
            .wrap(Wrap { trim: false }),
        chunks[3],
    );
}

fn event_type_label(event_type: &str) -> &str {
    match event_type {
        "competition" => "竞赛",
        "conference" => "会议",
        "journal_special_issue" => "期刊专题",
        "hackathon" => "黑客松",
        "summer_camp" => "夏令营",
        "pre_admission" => "预推免",
        _ => event_type,
    }
}

#[cfg(test)]
mod tests {
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    use super::*;

    fn rendered_text(app: &mut App) -> String {
        let backend = TestBackend::new(120, 32);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| draw(frame, frame.area(), app, &crate::theme::LIGHT))
            .unwrap();
        terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>()
            .replace(' ', "")
    }

    #[test]
    fn primary_query_tab_renders_the_shuttle_and_event_switch_at_the_top() {
        let mut app = App::new(false);
        app.selected_tab_index = 4;
        app.query_section = QuerySection::Shuttle;
        let text = rendered_text(&mut app);
        assert!(text.contains("查询"));
        assert!(text.contains("班车查询"));
        assert!(text.contains("重要事件查询"));
        assert!(text.contains("当前生效时刻表"));
    }

    #[test]
    fn primary_query_tab_renders_event_search_and_filter_controls() {
        let mut app = App::new(false);
        app.selected_tab_index = 4;
        app.query_section = QuerySection::Events;
        let text = rendered_text(&mut app);
        assert!(text.contains("查询"));
        assert!(text.contains("真实分类"));
        assert!(text.contains("仅收藏"));
        assert!(text.contains("详情与来源"));
    }
}
