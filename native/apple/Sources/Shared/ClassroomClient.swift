import Foundation

protocol ClassroomFetching: Sendable {
    func fetch(credentials: Credentials, targetDate: String) async throws -> ClassroomsCache
}

enum ClassroomClientError: LocalizedError {
    case service(String)

    var errorDescription: String? {
        switch self {
        case let .service(message): message
        }
    }
}

struct SJDClassroomClient: ClassroomFetching {
    private let api: SJDAPIClient

    init(session: URLSession = SJDURLSession.shared) {
        api = SJDAPIClient(session: session)
    }

    func fetch(credentials: Credentials, targetDate: String) async throws -> ClassroomsCache {
        guard targetDate == Self.contractDate() else {
            throw ClassroomClientError.service("空教室实时接口仅支持当天查询。")
        }
        let token = try await api.login(credentials: credentials)
        async let xitucheng = api.classrooms(token: token, campusID: "01")
        async let shahe = api.classrooms(token: token, campusID: "04")
        let payloads = try await ["01": xitucheng, "04": shahe]
        return try SJDClassroomParser.parse(
            payloads: payloads,
            targetDate: targetDate,
            fetchedAt: Self.timestamp()
        )
    }

    private static func contractDate(_ date: Date = .now) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    private static func timestamp(_ date: Date = .now) -> String {
        formatter("yyyy-MM-dd'T'HH:mm:ssXXX").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = format
        return formatter
    }
}

enum SJDClassroomParser {
    private struct ParsedClassroom {
        let building: String
        let room: String
        let size: Int?
    }

    private struct RoomAccumulator {
        let id: String
        let building: String
        let room: String
        let name: String
        var size: Int?
        var availableSlots = Set<Int>()
    }

    static func parse(
        payloads: [String: Data],
        targetDate: String,
        fetchedAt: String
    ) throws -> ClassroomsCache {
        let campuses = try ClassroomDefaults.campuses.map { campus in
            guard let data = payloads[campus.id] else {
                throw ClassroomClientError.service("缺少\(campus.name)校区实时教室数据。")
            }
            guard
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                SJDAPIClient.isSuccessful(payload)
            else {
                throw ClassroomClientError.service("\(campus.name)校区实时教室数据格式不正确。")
            }
            return parseCampus(
                campusID: campus.id,
                campusName: campus.name,
                items: payload["data"] as? [Any] ?? [],
                targetDate: targetDate,
                fetchedAt: fetchedAt
            )
        }
        return ClassroomsCache(
            cacheVersion: ClassroomDefaults.cacheVersion,
            targetDate: targetDate,
            fetchedAt: fetchedAt,
            realtime: true,
            provider: "sjd",
            campuses: campuses
        )
    }

    private static func parseCampus(
        campusID: String,
        campusName: String,
        items: [Any],
        targetDate: String,
        fetchedAt: String
    ) -> CampusClassrooms {
        var roomMap: [String: RoomAccumulator] = [:]
        for case let item as [String: Any] in items {
            let nodeName = firstString(in: item, keys: ["NODENAME", "nodeName", "nodename"])
            guard let slot = nodeNameToSlot(nodeName) else { continue }
            let classrooms = firstString(in: item, keys: ["CLASSROOMS", "classrooms", "Classrooms"])
            for raw in classrooms.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !raw.isEmpty {
                guard let parsed = parseClassroom(raw) else { continue }
                let inferred = inferTeachingExperimentSide(
                    building: normalizeBuildingName(parsed.building),
                    room: parsed.room
                )
                guard originalBuildings.contains(inferred.building) else { continue }
                guard let room = extractRoomName(inferred.room, building: inferred.building) else { continue }
                let key = "\(inferred.building)-\(room)"
                var accumulator = roomMap[key] ?? RoomAccumulator(
                    id: key,
                    building: inferred.building,
                    room: room,
                    name: key,
                    size: parsed.size
                )
                if accumulator.size == nil { accumulator.size = parsed.size }
                accumulator.availableSlots.insert(slot)
                roomMap[key] = accumulator
            }
        }
        let rooms = roomMap.values.map { item in
            Classroom(
                id: item.id,
                building: item.building,
                room: item.room,
                name: item.name,
                size: item.size,
                type: "",
                availableSlots: item.availableSlots.sorted(),
                source: "sjd"
            )
        }.sorted { ($0.building, $0.room) < ($1.building, $1.room) }
        return CampusClassrooms(
            campusID: campusID,
            campusName: campusName,
            targetDate: targetDate,
            fetchedAt: fetchedAt,
            realtime: true,
            provider: "sjd",
            rooms: rooms
        )
    }

    private static func parseClassroom(_ raw: String) -> ParsedClassroom? {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let size = firstCapture(pattern: #"[（(]\s*(\d+)\s*[）)]"#, in: clean).flatMap(Int.init)
        if let range = firstRange(pattern: #"[（(]\s*\d+\s*[）)]"#, in: clean) {
            clean = String(clean[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        clean = normalizeSeparators(clean)
        let parts = clean.split(separator: "-").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let building: String
        let room: String
        if parts.count >= 3, campusPrefixes.contains(parts[0]), let roomRange = clean.range(of: parts[2]) {
            building = String(clean[..<roomRange.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            room = String(clean[roomRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let separator = clean.firstIndex(of: "-") {
            building = String(clean[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            room = String(clean[clean.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            building = "未知教学楼"
            room = clean
        }
        return ParsedClassroom(
            building: building.isEmpty ? "未知教学楼" : building,
            room: room.isEmpty ? clean : room,
            size: size
        )
    }

    private static func normalizeBuildingName(_ value: String) -> String {
        let normalized = normalizeSeparators(value.trimmingCharacters(in: .whitespacesAndNewlines))
        let clean = campusPrefixes.compactMap { prefix -> String? in
            let fullPrefix = "\(prefix)-"
            return normalized.hasPrefix(fullPrefix) ? String(normalized.dropFirst(fullPrefix.count)) : nil
        }.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = clean.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        switch compact {
        case "1", "教一楼": return "教1"
        case "2", "教二楼": return "教2"
        case "3", "教三楼": return "教3"
        case "4", "教四楼": return "教4"
        case "未来学习大楼": return "主楼"
        case let value where northBuildings.contains(value): return "综合教学楼N"
        case let value where southBuildings.contains(value): return "综合教学楼S"
        case let value where experimentNorthBuildings.contains(value): return "教学实验综合楼N"
        case let value where experimentSouthBuildings.contains(value): return "教学实验综合楼S"
        case "智慧楼", "智慧教室楼", "智慧教室": return "智慧教学楼"
        case "": return "未知教学楼"
        default: return clean
        }
    }

    private static func inferTeachingExperimentSide(building: String, room: String) -> (building: String, room: String) {
        guard building == "教学实验综合楼" else { return (building, room) }
        let clean = normalizeSeparators(room.trimmingCharacters(in: .whitespacesAndNewlines))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
        guard let side = clean.first else { return (building, room) }
        let rest = clean.dropFirst().drop(while: { $0 == "-" })
        guard let first = rest.first, first.isASCII, first.isNumber else { return (building, room) }
        switch side {
        case "N", "n", "北": return ("教学实验综合楼N", String(rest))
        case "S", "s", "南": return ("教学实验综合楼S", String(rest))
        default: return (building, room)
        }
    }

    private static func extractRoomName(_ value: String, building: String) -> String? {
        var clean = normalizeSeparators(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if building.hasPrefix("教") {
            let number = String(building.dropFirst())
            for prefix in ["\(number)-", "教\(number)-"] where clean.hasPrefix(prefix) {
                clean = String(clean.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return firstMatch(pattern: #"\d{3}(?:-\d{3})?"#, in: clean)
    }

    private static func nodeNameToSlot(_ value: String) -> Int? {
        guard let number = firstMatch(pattern: #"\d+"#, in: value).flatMap(Int.init), (1 ... 14).contains(number) else {
            return nil
        }
        return number - 1
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String {
        keys.lazy.map { SJDAPIClient.string(object[$0]) }.first(where: { !$0.isEmpty }) ?? ""
    }

    private static func normalizeSeparators(_ value: String) -> String {
        value.replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
    }

    private static func firstMatch(pattern: String, in value: String) -> String? {
        guard let range = firstRange(pattern: pattern, in: value) else { return nil }
        return String(value[range])
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
            match.numberOfRanges > 1,
            let range = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[range])
    }

    private static func firstRange(pattern: String, in value: String) -> Range<String.Index>? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        return Range(match.range, in: value)
    }

    private static let campusPrefixes = Set(["校本部", "西土城", "沙河"])
    private static let originalBuildings = Set([
        "教1", "教2", "教3", "教4", "主楼", "综合教学楼N", "综合教学楼S",
        "教学实验综合楼N", "教学实验综合楼S", "智慧教学楼"
    ])
    private static let northBuildings = Set([
        "N", "N楼", "N座", "北楼", "综合教学楼N", "综合教学楼N楼", "综合教学楼N座",
        "综合楼N", "综合楼N楼", "综合N"
    ])
    private static let southBuildings = Set([
        "S", "S楼", "S座", "南楼", "综合教学楼S", "综合教学楼S楼", "综合教学楼S座",
        "综合楼S", "综合楼S楼", "综合S"
    ])
    private static let experimentNorthBuildings = Set([
        "教学实验综合楼N", "教学实验综合楼N楼", "教学实验综合楼N座", "教学实验综合楼北",
        "教学实验综合楼北楼", "教学实验综合楼-N", "教学实验综合楼-N楼",
        "教学实验综合楼(综教)N", "教学实验综合楼（综教）N", "教学实验综合楼N(综教)",
        "教学实验综合楼N（综教）", "综教N", "综教N楼", "综教N座", "综教北", "综教北楼",
        "综教-N", "综教-N楼"
    ])
    private static let experimentSouthBuildings = Set([
        "教学实验综合楼S", "教学实验综合楼S楼", "教学实验综合楼S座", "教学实验综合楼南",
        "教学实验综合楼南楼", "教学实验综合楼-S", "教学实验综合楼-S楼",
        "教学实验综合楼(综教)S", "教学实验综合楼（综教）S", "教学实验综合楼S(综教)",
        "教学实验综合楼S（综教）", "综教S", "综教S楼", "综教S座", "综教南", "综教南楼",
        "综教-S", "综教-S楼"
    ])
}
