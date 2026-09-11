import Foundation
import CryptoKit

enum CourseDeletionScope: String, Codable, Sendable {
    case occurrence
    case course
}

struct CourseDeletion: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let accountScope: String
    let termID: String
    let sourceCourseID: String?
    let name: String
    let teacher: String
    let scope: CourseDeletionScope
    let date: String?
    let startSlot: Int
    let endSlot: Int

    init(account: String, termID: String, course: Course, date: Date, scope: CourseDeletionScope) {
        id = UUID().uuidString
        accountScope = CourseDeletionLogic.accountKey(account)
        self.termID = termID
        sourceCourseID = course.sourceCourseID
        name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
        teacher = course.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        self.date = scope == .occurrence ? StrictContractDateParser.string(from: date) : nil
        startSlot = course.startSlot
        endSlot = course.endSlot
    }

    func matches(_ course: Course) -> Bool {
        let storedID = sourceCourseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidateID = course.sourceCourseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedID.isEmpty, !candidateID.isEmpty { return storedID == candidateID }
        return name == course.name.trimmingCharacters(in: .whitespacesAndNewlines)
            && teacher == course.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CourseDeletionLogic {
    static func accountKey(_ account: String) -> String {
        let normalized = account.trimmingCharacters(in: .whitespacesAndNewlines)
        return "sha256:" + SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func applying(_ deletions: [CourseDeletion], to snapshot: ScheduleSnapshot, account: String) -> ScheduleSnapshot {
        let scope = accountKey(account)
        let relevant = deletions.filter {
            $0.accountScope == scope
                && $0.termID == snapshot.termID
        }
        guard !relevant.isEmpty else { return snapshot }
        let termStart = StrictContractDateParser.date(from: snapshot.termStartDate)
        let calendar = Calendar.shanghai
        let courses = snapshot.courses.compactMap { course -> Course? in
            let matching = relevant.filter { $0.matches(course) }
            guard !matching.contains(where: { $0.scope == .course }) else { return nil }
            guard let termStart, (1 ... 7).contains(course.weekday) else { return course }
            let weeks = course.weekNumbers.filter { week in
                guard week > 0 else { return true }
                let (weekOffset, weekOverflow) = (week - 1).multipliedReportingOverflow(by: 7)
                let (dayOffset, dayOverflow) = weekOffset.addingReportingOverflow(course.weekday - 1)
                guard !weekOverflow, !dayOverflow,
                      let date = calendar.date(byAdding: .day, value: dayOffset, to: termStart)
                else { return true }
                let day = StrictContractDateParser.string(from: date)
                return !matching.contains {
                    $0.scope == .occurrence && $0.date == day
                        && $0.startSlot == course.startSlot && $0.endSlot == course.endSlot
                }
            }
            guard !weeks.isEmpty else { return nil }
            return Course(
                id: course.id, name: course.name, teacher: course.teacher, room: course.room,
                weekText: course.weekText, weekNumbers: weeks, examWeekNumbers: course.examWeekNumbers,
                weekday: course.weekday, startSlot: course.startSlot, endSlot: course.endSlot,
                sectionText: course.sectionText, timeRange: course.timeRange,
                sourceCourseID: course.sourceCourseID
            )
        }
        return ScheduleSnapshot(termID: snapshot.termID, termStartDate: snapshot.termStartDate,
                                fetchedAt: snapshot.fetchedAt, courses: courses)
    }
}

protocol CourseDeletionStoring: Sendable {
    func load() throws -> [CourseDeletion]
    func save(_ deletions: [CourseDeletion]) throws
    func clear() throws
}

enum CourseDeletionStoreError: Error {
    case oversizedFile
    case tooManyRecords
    case notRegularFile
}

struct FileCourseDeletionStore: CourseDeletionStoring {
    static let maximumPayloadBytes = 1024 * 1024
    static let maximumRecordCount = 1000
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if fileURL == nil, AppLaunchConfiguration.isXCTestRunning {
            self.fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WhereToStudyCourseDeletionTests-\(UUID().uuidString)")
                .appendingPathComponent("course-deletions.json")
            return
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? root.appendingPathComponent("WhereToStudyNative", isDirectory: true)
            .appendingPathComponent("course-deletions.json")
    }

    func load() throws -> [CourseDeletion] {
        let metadata: [FileAttributeKey: Any]
        do {
            metadata = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        guard metadata[.type] as? FileAttributeType == .typeRegular else { throw CourseDeletionStoreError.notRegularFile }
        guard (metadata[.size] as? NSNumber)?.uint64Value ?? 0 <= UInt64(Self.maximumPayloadBytes) else { throw CourseDeletionStoreError.oversizedFile }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumPayloadBytes + 1) ?? Data()
        guard data.count <= Self.maximumPayloadBytes else { throw CourseDeletionStoreError.oversizedFile }
        let records = try JSONDecoder().decode([CourseDeletion].self, from: data)
        guard records.count <= Self.maximumRecordCount else { throw CourseDeletionStoreError.tooManyRecords }
        return records
    }

    func save(_ deletions: [CourseDeletion]) throws {
        guard deletions.count <= Self.maximumRecordCount else { throw CourseDeletionStoreError.tooManyRecords }
        let data = try JSONEncoder().encode(deletions)
        guard data.count <= Self.maximumPayloadBytes else { throw CourseDeletionStoreError.oversizedFile }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        do { try FileManager.default.removeItem(at: fileURL) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { }
    }
}
