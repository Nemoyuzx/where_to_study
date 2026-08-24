fn main() {
    const COMMANDS: &[&str] = &[
        "get_metadata",
        "load_saved_settings",
        "save_saved_settings",
        "clear_local_data",
        "load_saved_schedule",
        "load_saved_schedule_for_scope",
        "load_saved_classrooms",
        "load_saved_classrooms_for_scope",
        "fetch_schedule",
        "import_schedule_to_calendar",
        "import_favorite_deadlines_to_calendar",
        "fetch_classrooms",
        "fetch_holidays",
        "fetch_weather",
        "fetch_almanac",
        "fetch_deadlines",
        "fetch_assignments",
        "fetch_deadline_calendar",
        "fetch_custom_deadline_calendar",
        "fetch_assignment_calendar",
    ];

    tauri_build::try_build(
        tauri_build::Attributes::new()
            .app_manifest(tauri_build::AppManifest::new().commands(COMMANDS)),
    )
    .expect("failed to build Tauri application metadata");
}
