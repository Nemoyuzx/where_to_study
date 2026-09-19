use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::Modifier;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Borders, Cell, Paragraph, Row, Table, TableState, Tabs, Wrap};
use ratatui::Frame;

use crate::app::{App, QuerySection};
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, app: &mut App, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(if app.query_section == QuerySection::Grades {
                5
            } else {
                3
            }),
            Constraint::Min(5),
            Constraint::Length(7),
        ])
        .split(area);

    let selected = match app.query_section {
        QuerySection::Shuttle => 0,
        QuerySection::Events => 1,
        QuerySection::Grades => 2,
    };
    let labels = if area.width < 64 {
        ["班车", "事件", "成绩"]
    } else {
        ["班车查询", "重要事件查询", "成绩查询"]
    };
    let tabs = Tabs::new(labels)
        .select(selected)
        .highlight_style(theme.primary_selected().add_modifier(Modifier::BOLD))
        .divider("  ")
        .block(theme.control_block().borders(Borders::ALL).title("查询"));
    frame.render_widget(tabs, chunks[0]);

    match app.query_section {
        QuerySection::Shuttle => draw_shuttle(frame, &chunks, app, theme),
        QuerySection::Events => draw_events(frame, &chunks, app, theme),
        QuerySection::Grades => draw_grades(frame, &chunks, app, theme),
    }
}

fn draw_grades(frame: &mut Frame, chunks: &[Rect], app: &App, theme: &Theme) {
    let controls = format!(
        "{} · {}\nt 学期 · p 记录 · a 全部学期 · r 刷新 · s 设置",
        app.grade_term_label(),
        app.grade_type_label()
    );
    frame.render_widget(
        Paragraph::new(controls).wrap(Wrap { trim: false }).block(
            theme
                .control_block()
                .borders(Borders::ALL)
                .title("学校成绩查询"),
        ),
        chunks[1],
    );
    if let Some(report) = &app.grades {
        let rows = report.items.iter().map(|item| {
            Row::new([
                Cell::from(item.name.as_str()),
                Cell::from(if item.score.is_empty() {
                    "未公布"
                } else {
                    &item.score
                }),
                Cell::from(if item.credits.is_empty() {
                    "未公布"
                } else {
                    &item.credits
                }),
            ])
        });
        let gpa = if report.average_grade_point.is_empty() {
            String::new()
        } else {
            format!(" · 平均学分绩点 {}", report.average_grade_point)
        };
        let table = Table::new(
            rows,
            [
                Constraint::Min(12),
                Constraint::Length(9),
                Constraint::Length(8),
            ],
        )
        .header(Row::new(["课程", "成绩", "学分"]).style(theme.strong_text()))
        .row_highlight_style(theme.primary_selected())
        .block(
            theme
                .card_block()
                .borders(Borders::ALL)
                .title(format!("{} 项成绩{gpa}", report.items.len())),
        );
        let mut state = TableState::default().with_selected(Some(app.grade_cursor));
        frame.render_stateful_widget(table, chunks[2], &mut state);
    } else {
        let text = if app.grades_loading() {
            "正在向学校查询成绩…"
        } else {
            app.grade_error
                .as_deref()
                .unwrap_or("尚未查询成绩；r 查询，s 前往账户设置。")
        };
        frame.render_widget(
            Paragraph::new(text)
                .wrap(Wrap { trim: false })
                .block(theme.card_block().borders(Borders::ALL).title("成绩")),
            chunks[2],
        );
    }
    let detail = app
        .grades
        .as_ref()
        .and_then(|report| report.items.get(app.grade_cursor))
        .map_or_else(
            || {
                if app
                    .grades
                    .as_ref()
                    .is_some_and(|report| report.items.is_empty())
                {
                    "所选学期暂无已公布成绩，按 a 查看全部学期。".into()
                } else {
                    "成绩仅在内存保留；账号或凭据变更后清除。".into()
                }
            },
            |item| {
                format!(
                    "{}\n{}\n{} · {} · {}\n课程代码：{} · 成绩标识：{}",
                    item.name,
                    item.semester_name,
                    item.course_attribute,
                    item.course_nature,
                    item.exam_nature,
                    item.course_code,
                    item.grade_status
                )
            },
        );
    let detail = match &app.grade_error {
        Some(error) if app.grades.is_some() => format!("{error}\n正在显示此前结果。\n{detail}"),
        Some(error) => error.clone(),
        None => detail,
    };
    frame.render_widget(
        Paragraph::new(detail).wrap(Wrap { trim: false }).block(
            theme
                .elevated_block()
                .borders(Borders::ALL)
                .title("成绩详情 · ↑↓ / PgUp PgDn"),
        ),
        chunks[3],
    );
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
            .block(theme.card_block().borders(Borders::ALL).title("今日状态")),
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
                theme
                    .card_block()
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
            .block(theme.card_block().borders(Borders::ALL).title("来源声明"))
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
                theme
                    .control_block()
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
                Line::from(content).style(theme.primary_selected().add_modifier(Modifier::BOLD))
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
        .block(theme.card_block().borders(Borders::ALL).title(title)),
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
            .block(
                theme
                    .elevated_block()
                    .borders(Borders::ALL)
                    .title("详情与来源"),
            )
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
        rendered_text_at_size(app, 120, 32)
    }

    fn rendered_text_at_size(app: &mut App, width: u16, height: u16) -> String {
        let backend = TestBackend::new(width, height);
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
    fn grade_query_renders_zero_text_grades_and_narrow_terminal_controls() {
        use where_to_study_lib::academic::{GradeItem, GradeReport};
        let mut app = App::new(false);
        app.query_section = QuerySection::Grades;
        app.grade_term = Some(String::new());
        app.grades = Some(GradeReport {
            items: vec![
                GradeItem {
                    name: "合成零分".into(),
                    score: "0".into(),
                    credits: "0".into(),
                    ..Default::default()
                },
                GradeItem {
                    name: "合成文字".into(),
                    score: "优秀".into(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        });
        let wide = rendered_text(&mut app);
        assert!(wide.contains("成绩查询"));
        assert!(wide.contains("合成零分"));
        assert!(wide.contains("优秀"));
        assert!(!wide.contains("平均学分绩点"));
        for (width, height) in [(40, 22), (80, 24), (120, 32)] {
            let text = rendered_text_at_size(&mut app, width, height);
            assert!(text.contains("成绩"));
            assert!(text.contains("全部学期"));
            assert!(text.contains("合成零分"));
        }
        app.grade_error = Some("合成查询失败".into());
        assert!(rendered_text(&mut app).contains("正在显示此前结果"));
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
