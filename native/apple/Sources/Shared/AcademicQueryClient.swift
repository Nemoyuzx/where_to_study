import CryptoKit
import Foundation

struct AcademicTerm: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct GradeItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let score: String?
    let credits: String?
    let courseCode: String?
    let courseAttribute: String?
    let courseNature: String?
    let examNature: String?
    var semesterName: String? = nil
    var gradeStatus: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, score, credits
        case courseCode = "course_code"
        case courseAttribute = "course_attribute"
        case courseNature = "course_nature"
        case examNature = "exam_nature"
        case semesterName = "semester_name"
        case gradeStatus = "grade_status"
    }
}

struct GradeSnapshot: Codable, Equatable, Sendable {
    let termID: String
    let recordType: String
    let fetchedAt: String
    let averageGradePoint: String?
    let items: [GradeItem]

    enum CodingKeys: String, CodingKey {
        case items
        case termID = "term_id"
        case recordType = "record_type"
        case fetchedAt = "fetched_at"
        case averageGradePoint = "average_grade_point"
    }
}

struct GradeQueryResult: Codable, Sendable {
    let currentTermID: String
    let terms: [AcademicTerm]
    let snapshot: GradeSnapshot

    enum CodingKeys: String, CodingKey {
        case terms, snapshot
        case currentTermID = "current_term_id"
    }
}

enum AcademicResponseParser {
    static func rows(_ data: Data) throws -> [[String: Any]] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              scalar(object["code"]) == "1", let rows = object["data"] as? [[String: Any]]
        else { throw ScheduleClientError.invalidResponse("成绩或考试数据格式无法识别，请重新登录后重试。") }
        return rows
    }

    static func scalar(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }

    static func stableID(_ fields: [String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func terms(_ data: Data) throws -> [AcademicTerm] {
        var seen = Set<String>()
        return try rows(data).map { row in
            guard let id = scalar(row["semesterId"]), !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ScheduleClientError.invalidResponse("学校学期列表无法识别，请稍后重试。")
            }
            return AcademicTerm(id: id, name: scalar(row["semesterName"]) ?? id)
        }.filter { seen.insert($0.id).inserted }
    }

    static func grades(_ data: Data, termID: String, recordType: String) throws -> GradeSnapshot {
        let rows = try rows(data)
        guard rows.count <= 1 else { throw ScheduleClientError.invalidResponse("成绩数据格式无法识别，请稍后重试。") }
        let details: [[String: Any]]
        if let row = rows.first {
            guard let achievement = row["achievement"] as? [[String: Any]] else {
                throw ScheduleClientError.invalidResponse("成绩数据格式无法识别，请稍后重试。")
            }
            details = achievement
        } else { details = [] }
        var seen = Set<String>()
        let items = try details.map { row in
            guard let name = scalar(row["courseName"]), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ScheduleClientError.invalidResponse("成绩数据格式无法识别，请稍后重试。")
            }
            let score = scalar(row["fraction"])
            let credits = scalar(row["credit"])
            let code = scalar(row["kcbh"])
            let attribute = scalar(row["curriculumAttributes"])
            let nature = scalar(row["courseNature"])
            let examNature = scalar(row["examinationNature"])
            let semesterName = scalar(row["curSemesterName"])
            let gradeStatus = scalar(row["cjbs"])
            let sourceID = scalar(row["cj0708id"])
            let identity = sourceID.map { ["school-grade", $0] }
                ?? [termID, semesterName ?? "", name, score ?? "", credits ?? "", code ?? "", attribute ?? "", nature ?? "", examNature ?? "", gradeStatus ?? ""]
            return GradeItem(id: stableID(identity),
                             name: name, score: score, credits: credits, courseCode: code,
                             courseAttribute: attribute, courseNature: nature, examNature: examNature,
                             semesterName: semesterName, gradeStatus: gradeStatus)
        }.filter { seen.insert($0.id).inserted }
        return GradeSnapshot(termID: termID, recordType: recordType, fetchedAt: SJDClassroomClient.timestamp(.now),
                             averageGradePoint: scalar(rows.first?["pjxfjd"]), items: items)
    }

    /// Recognize a complete date and explicit clock range only. Unrecognized
    /// school text remains visible and never supplies guessed timetable slots.
    static func examTime(_ value: String) -> (date: String, start: String, end: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = String(text.prefix(10))
        guard StrictContractDateParser.date(from: date) != nil else { return ("", "", "") }
        guard text.count > 10 else { return (date, "", "") }
        guard let separator = text.dropFirst(10).first, separator.isWhitespace || separator == "T" else { return ("", "", "") }
        let pattern = #"^\d{4}-\d{2}-\d{2}[ T]+(\d{2}:\d{2})(?:\s*[-~～—至]\s*)(\d{2}:\d{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let first = Range(match.range(at: 1), in: text), let last = Range(match.range(at: 2), in: text)
        else { return (date, "", "") }
        let start = String(text[first]), end = String(text[last])
        guard let startMinute = AcademicTime.minute(start), let endMinute = AcademicTime.minute(end), startMinute < endMinute
        else { return (date, "", "") }
        return (date, start, end)
    }

    static func exams(_ data: Data, termID: String, accountKey: String) throws -> ExamSchedule {
        var seen = Set<String>()
        let items = try rows(data).map { row in
            guard let name = scalar(row["courseName"]), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ScheduleClientError.invalidResponse("考试安排格式无法识别，请稍后重试。")
            }
            let primary = scalar(row["time"]) ?? ""
            let auxiliary = [scalar(row["ksqssj"]), scalar(row["zssj1"]), scalar(row["zssj2"])].compactMap { $0 }
            let hasPrimary = !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let timeText = hasPrimary ? primary : auxiliary.joined(separator: " ")
            var time = examTime(timeText)
            if !hasPrimary {
                let date = (scalar(row["ksqssj"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let start = (scalar(row["zssj1"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let end = (scalar(row["zssj2"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if StrictContractDateParser.date(from: date) != nil,
                   let first = AcademicTime.minute(start), let last = AcademicTime.minute(end), first < last {
                    // Separate clock fields define the range; keep their
                    // original joined text without inventing a delimiter.
                    time = (date, start, end)
                }
            }
            let room = scalar(row["examinationPlace"]) ?? ""
            return ExamArrangement(id: "exam-" + stableID([termID, name, room, timeText]), name: name,
                                   date: time.date, startTime: time.start, endTime: time.end,
                                   room: room, seat: "", timeText: timeText)
        }.filter { seen.insert($0.id).inserted }
        return ExamSchedule(termID: termID, accountKey: accountKey, fetchedAt: SJDClassroomClient.timestamp(.now),
                            status: "fresh", message: "", items: items)
    }
}

protocol GradeFetching: Sendable {
    func fetch(credentials: Credentials, termID: String?, recordType: String) async throws -> GradeQueryResult
}

enum ExamScheduleCachePolicy {
    static func resolve(_ incoming: ExamSchedule?, previous: ExamSchedule?, termID: String, accountKey: String) -> ExamSchedule? {
        guard let incoming, incoming.termID == termID, incoming.accountKey == accountKey,
              ["fresh", "failed", "stale"].contains(incoming.status) else { return nil }
        guard incoming.status == "failed", var previous,
              previous.termID == termID, previous.accountKey == accountKey,
              ["fresh", "stale"].contains(previous.status) else { return incoming }
        previous.status = "stale"
        previous.message = "考试安排更新失败，当前展示上次成功同步的安排。"
        return previous
    }
}

struct SJDGradeClient: GradeFetching {
    let api: SJDAPIClient
    init(api: SJDAPIClient = SJDAPIClient()) { self.api = api }

    func fetch(credentials: Credentials, termID: String?, recordType: String) async throws -> GradeQueryResult {
        guard ["", "0", "1"].contains(recordType) else { throw ScheduleClientError.invalidResponse("成绩记录类型无效。") }
        return try await api.authenticated(credentials: credentials) { token in
            async let currentData = api.academic(token: token, endpoint: .currentTerm)
            async let termData = api.academic(token: token, endpoint: .semesterList)
            let current = try AcademicResponseParser.terms(await currentData)
            let terms = try AcademicResponseParser.terms(await termData)
            guard let currentTermID = current.first?.id else { throw ScheduleClientError.invalidResponse("学校当前学期无法识别，请稍后重试。") }
            let selected = termID ?? currentTermID
            guard selected.isEmpty || terms.contains(where: { $0.id == selected }) else {
                throw ScheduleClientError.invalidResponse("所选学期不在学校学期列表中，请刷新重试。")
            }
            let data = try await api.academic(token: token, endpoint: .grades, parameters: ["semester": selected, "type": recordType])
            return GradeQueryResult(currentTermID: currentTermID, terms: terms,
                                    snapshot: try AcademicResponseParser.grades(data, termID: selected, recordType: recordType))
        }
    }
}
