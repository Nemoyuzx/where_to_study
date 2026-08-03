import Foundation

protocol ClassroomStoring: Sendable {
    func load() throws -> ClassroomsCache?
    func save(_ cache: ClassroomsCache) throws
}

struct FileClassroomStore: ClassroomStoring {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func load() throws -> ClassroomsCache? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        let cache = try JSONDecoder().decode(ClassroomsCache.self, from: data)
        return cache.cacheVersion >= ClassroomDefaults.cacheVersion ? cache : nil
    }

    func save(_ cache: ClassroomsCache) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cache).write(to: fileURL, options: .atomic)
    }

    private static var defaultFileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("WhereToStudyNative", isDirectory: true)
            .appendingPathComponent("classrooms.json", isDirectory: false)
    }
}
