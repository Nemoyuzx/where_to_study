fn main() {
    const COMMANDS: &[&str] = &[
        "get_metadata",
        "load_saved_settings",
        "save_saved_settings",
        "clear_local_data",
        "load_saved_schedule",
        "load_saved_classrooms",
        "fetch_schedule",
        "import_schedule_to_calendar",
        "fetch_classrooms",
        "fetch_holidays",
        "show_desktop_widget",
        "hide_desktop_widget",
    ];

    tauri_build::try_build(
        tauri_build::Attributes::new()
            .app_manifest(tauri_build::AppManifest::new().commands(COMMANDS)),
    )
    .expect("failed to build Tauri application metadata");
}
