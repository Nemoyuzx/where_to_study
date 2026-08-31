use clap::{Parser, Subcommand};

mod commands;
mod credentials;
mod output;

#[derive(Parser)]
#[command(
    name = "where-to-study-cli",
    version,
    about = "Where To Study 命令行客户端 - 北邮课表与空教室查询",
    long_about = "Where To Study 命令行客户端

基于与桌面版相同的数据源，支持个人课表、空教室、节假日、班车与重要事件查询。
支持 macOS 与 Linux，账号密码保存在当前用户专属的本地配置文件中。"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 保存教务账号（交互输入密码），已保存时留空密码保持不变
    Login {
        /// 教务学号；省略时在终端中隐藏输入
        account: Option<String>,
    },
    /// 清除已保存的教务凭据
    Logout,
    /// 显示某天的课程（默认今天）
    Schedule {
        /// 目标日期 yyyy-MM-dd（默认今天，按上海时区）
        #[arg(long)]
        date: Option<String>,
        /// 以 JSON 输出
        #[arg(long)]
        json: bool,
    },
    /// 显示本周课程
    Week {
        /// 周内任意日期 yyyy-MM-dd（默认今天）
        #[arg(long)]
        date: Option<String>,
        /// 以 JSON 输出
        #[arg(long)]
        json: bool,
    },
    /// 查询当天空教室
    Classrooms {
        /// 校区编号：01 西土城 / 04 沙河
        #[arg(long, default_value = "01")]
        campus: String,
        /// 教学楼名称（如 教1、综合教学楼N），可重复指定
        #[arg(long)]
        building: Vec<String>,
        /// 节次筛选，如 1-3,5（默认全部空闲节次）
        #[arg(long)]
        slots: Option<String>,
        /// 以 JSON 输出
        #[arg(long)]
        json: bool,
    },
    /// 显示中国法定节假日与调休（默认今年）
    Holidays {
        /// 年份
        #[arg(long)]
        year: Option<i32>,
        /// 以 JSON 输出
        #[arg(long)]
        json: bool,
    },
    /// 查询今天当前生效的两校区班车时刻表
    Shuttle {
        /// 以 JSON 输出（包含来源元数据和当天状态）
        #[arg(long)]
        json: bool,
    },
    /// 查询公开活动与校内竞赛通知（不包含作业和自定义日程）
    Events {
        /// 搜索名称、主办方、类别、标签、地点或说明
        #[arg(long)]
        search: Option<String>,
        /// 事件类型，如 competition、conference、hackathon
        #[arg(long = "type")]
        event_type: Option<String>,
        /// 真实数据类别，如 人工智能、校内竞赛通知
        #[arg(long)]
        category: Option<String>,
        /// 来源：all / public / school
        #[arg(long, default_value = "all", value_parser = ["all", "public", "school"])]
        source: String,
        /// 同时显示已经截止的事件（默认隐藏）
        #[arg(long)]
        include_ended: bool,
        /// 只显示本地收藏
        #[arg(long)]
        favorites_only: bool,
        /// 收藏指定结果 ID 或输出中的 favorite_key
        #[arg(long, conflicts_with = "unfavorite")]
        favorite: Option<String>,
        /// 取消收藏指定结果 ID 或 favorite_key
        #[arg(long)]
        unfavorite: Option<String>,
        /// 以 JSON 输出（包含筛选条件、来源元数据与收藏状态）
        #[arg(long)]
        json: bool,
    },
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let result = match cli.command {
        Commands::Login { account } => commands::login(account),
        Commands::Logout => commands::logout(),
        Commands::Schedule { date, json } => commands::schedule(date, json).await,
        Commands::Week { date, json } => commands::week(date, json).await,
        Commands::Classrooms {
            campus,
            building,
            slots,
            json,
        } => commands::classrooms(campus, building, slots, json).await,
        Commands::Holidays { year, json } => commands::holidays(year, json).await,
        Commands::Shuttle { json } => commands::shuttle(json).await,
        Commands::Events {
            search,
            event_type,
            category,
            source,
            include_ended,
            favorites_only,
            favorite,
            unfavorite,
            json,
        } => {
            commands::events(commands::EventsOptions {
                search,
                event_type,
                category,
                source,
                include_ended,
                favorites_only,
                favorite,
                unfavorite,
                json,
            })
            .await
        }
    };

    if let Err(error) = result {
        eprintln!("错误：{error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn login_does_not_accept_password_in_process_arguments() {
        assert!(Cli::try_parse_from([
            "where-to-study-cli",
            "login",
            "2023000000",
            "--password",
            "secret"
        ])
        .is_err());
    }

    #[test]
    fn login_can_prompt_for_account_without_process_arguments() {
        assert!(Cli::try_parse_from(["where-to-study-cli", "login"]).is_ok());
    }

    #[test]
    fn classrooms_does_not_accept_non_today_date() {
        assert!(
            Cli::try_parse_from(["where-to-study-cli", "classrooms", "--date", "2026-09-01",])
                .is_err()
        );
    }

    #[test]
    fn public_queries_do_not_accept_custom_endpoints_or_assignments() {
        assert!(Cli::try_parse_from([
            "where-to-study-cli",
            "shuttle",
            "--url",
            "https://example.com/data.json"
        ])
        .is_err());
        assert!(
            Cli::try_parse_from(["where-to-study-cli", "events", "--source", "assignment"])
                .is_err()
        );
    }

    #[test]
    fn events_exposes_search_filter_and_favorite_controls() {
        assert!(Cli::try_parse_from([
            "where-to-study-cli",
            "events",
            "--search",
            "人工智能",
            "--type",
            "conference",
            "--category",
            "人工智能",
            "--source",
            "public",
            "--include-ended",
            "--favorites-only",
            "--json"
        ])
        .is_ok());
        assert!(Cli::try_parse_from([
            "where-to-study-cli",
            "events",
            "--favorite",
            "contest_ddl:conference-1",
            "--unfavorite",
            "contest_ddl:conference-1"
        ])
        .is_err());
    }
}
