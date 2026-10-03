import SwiftUI

// Settings keeps these references without subscribing. Only the editors
// observe their drafts, including when adaptive columns recreate the editors.
@MainActor
final class SettingsPreClassReminderDraft: ObservableObject {
    @Published var minuteFields = ["10"]
    @Published var validationFailed = false
    @Published var saved = false
    private var savedOffsets: [Int]?

    func synchronize(with offsets: [Int]) {
        guard savedOffsets != offsets else { return }
        reset(to: offsets)
    }

    func reset(to offsets: [Int]) {
        savedOffsets = offsets
        minuteFields = offsets.map(String.init)
        validationFailed = false
        saved = false
    }
}

@MainActor
final class SettingsColorThemeDraft: ObservableObject {
    @Published var primary = "#166B5D"
    @Published var accent = "#E2BC62"
    @Published var selectedDate = "#2563EB"
    @Published var hasEdited = false
    private var savedSeeds: ColorThemeSeeds?

    func synchronize(with seeds: ColorThemeSeeds) {
        guard savedSeeds != seeds else { return }
        reset(to: seeds)
    }

    func reset(to seeds: ColorThemeSeeds) {
        savedSeeds = seeds
        primary = seeds.primary.hex
        accent = seeds.accent.hex
        selectedDate = seeds.selectedDate.hex
        hasEdited = false
    }
}
