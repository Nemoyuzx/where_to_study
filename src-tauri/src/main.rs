// Release builds are GUI applications; debug builds keep their console output.
#![cfg_attr(
    all(target_os = "windows", not(debug_assertions)),
    windows_subsystem = "windows"
)]

fn main() {
    where_to_study_lib::run()
}
