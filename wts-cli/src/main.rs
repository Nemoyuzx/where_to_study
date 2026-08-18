use clap::{Parser, Subcommand};

mod commands;
mod credentials;
mod output;

#[derive(Parser)]
#[command(
    name = "wts-cli",
    version,
    about = "Where To Study 命令行客户端 - 北邮课表与空教室查询",
    long_about = "Where To Study 命令行客户端

基于与桌面版相同的数据源（移动教务 HTTPS 接口），支持个人课表、空教室、节假日查询。
账号密码保存在系统凭据存储（macOS Keychain / Windows Credential Manager / Linux Secret Service）。"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// 保存教务账号（交互输入密码），已保存时留空密码保持不变
    Login {
        /// 教务学号
        account: String,
        /// 直接提供密码（不推荐，会出现在 shell 历史中）
        #[arg(long)]
        password: Option<String>,
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
        /// 目标日期 yyyy-MM-dd（默认今天）
        #[arg(long)]
        date: Option<String>,
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
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let result = match cli.command {
        Commands::Login { account, password } => commands::login(account, password),
        Commands::Logout => commands::logout(),
        Commands::Schedule { date, json } => commands::schedule(date, json).await,
        Commands::Week { date, json } => commands::week(date, json).await,
        Commands::Classrooms {
            campus,
            building,
            slots,
            date,
            json,
        } => commands::classrooms(campus, building, slots, date, json).await,
        Commands::Holidays { year, json } => commands::holidays(year, json).await,
    };

    if let Err(error) = result {
        eprintln!("错误：{error}");
        std::process::exit(1);
    }
}
