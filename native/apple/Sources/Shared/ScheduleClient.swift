import CryptoKit
import Foundation

protocol ScheduleFetching: Sendable {
    func fetch(
        credentials: Credentials,
        fallbackTermID: String,
        fallbackTermStartDate: String
    ) async throws -> ScheduleSnapshot
}

enum ScheduleClientError: LocalizedError {
    case missingCredentials
    case invalidResponse(String)
    case service(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "请先在设置中填写并保存教务账号和密码。"
        case let .invalidResponse(message), let .service(message):
            message
        }
    }
}

struct SJDScheduleClient: ScheduleFetching {
    private static let origin = "http://jwglweixin.bupt.edu.cn"
    private static let loginURL = URL(string: "\(origin)/bjyddx/login")!
    private static let curriculumURL = URL(string: "\(origin)/bjyddx/student/curriculum")!
    private static let loginReferer = "\(origin)/sjd/#/login"
    private static let curriculumReferer = "\(origin)/sjd/#/restClassroom"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(
        credentials: Credentials,
        fallbackTermID: String,
        fallbackTermStartDate: String
    ) async throws -> ScheduleSnapshot {
        let account = credentials.account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !credentials.password.isEmpty else {
            throw ScheduleClientError.missingCredentials
        }

        let token = try await login(account: account, password: credentials.password)
        async let currentData = curriculum(token: token, week: "")
        async let allData = curriculum(token: token, week: "all")
        return try SJDScheduleParser.parse(
            currentData: await currentData,
            curriculumData: await allData,
            fallbackTermID: fallbackTermID,
            fallbackTermStartDate: fallbackTermStartDate
        )
    }

    private func login(account: String, password: String) async throws -> String {
        var request = URLRequest(url: Self.loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = formData(["userNo": account, "pwd": password])
        applyHeaders(to: &request, referer: Self.loginReferer, token: nil)

        let payload = try await responseObject(for: request, failureMessage: "无法连接移动教务服务。")
        guard Self.isSuccessful(payload) else {
            throw ScheduleClientError.service(Self.message(in: payload, fallback: "移动教务登录失败。"))
        }
        guard
            let data = payload["data"] as? [String: Any],
            let token = data["token"] as? String,
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ScheduleClientError.invalidResponse("移动教务登录成功但没有返回 token。")
        }
        return token
    }

    private func curriculum(token: String, week: String) async throws -> Data {
        var components = URLComponents(url: Self.curriculumURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "week", value: week)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        applyHeaders(to: &request, referer: Self.curriculumReferer, token: token)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw ScheduleClientError.service("移动教务课表获取失败。")
        }
        guard
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            Self.isSuccessful(payload)
        else {
            throw ScheduleClientError.invalidResponse("移动教务课表返回了无法识别的数据。")
        }
        return data
    }

    private func responseObject(for request: URLRequest, failureMessage: String) async throws -> [String: Any] {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
                throw ScheduleClientError.service(failureMessage)
            }
            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ScheduleClientError.invalidResponse("移动教务返回了无法识别的数据。")
            }
            return payload
        } catch let error as ScheduleClientError {
            throw error
        } catch {
            throw ScheduleClientError.service(failureMessage)
        }
    }

    private func applyHeaders(to request: inout URLRequest, referer: String, token: String?) {
        request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue(token, forHTTPHeaderField: "token") }
    }

    private func formData(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private static func isSuccessful(_ payload: [String: Any]) -> Bool {
        string(payload["code"]) == "1"
    }

    private static func message(in payload: [String: Any], fallback: String) -> String {
        string(payload["Msg"]).nilIfEmpty ?? string(payload["msg"]).nilIfEmpty ?? fallback
    }

    fileprivate static func string(_ value: Any?) -> String {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: ""
        }
    }
}

enum SJDScheduleParser {
    static func parse(
        currentData: Data,
        curriculumData: Data,
        fallbackTermID: String,
        fallbackTermStartDate: String,
        fetchedAt: Date = .now
    ) throws -> ScheduleSnapshot {
        guard
            let current = try JSONSerialization.jsonObject(with: currentData) as? [String: Any],
            let curriculum = try JSONSerialization.jsonObject(with: curriculumData) as? [String: Any],
            let currentRoot = (current["data"] as? [Any])?.first as? [String: Any],
            let curriculumRoot = (curriculum["data"] as? [Any])?.first as? [String: Any]
        else {
            throw ScheduleClientError.invalidResponse("移动教务课表返回为空。")
        }

        let termID = [currentRoot["semesterId"], currentRoot["xnxq01id"]]
            .map(SJDScheduleClient.string)
            .first(where: { !$0.isEmpty }) ?? fallbackTermID
        let termStartDate = inferTermStartDate(from: currentRoot) ?? fallbackTermStartDate
        let rawRoot = curriculumRoot["item"] ?? curriculumRoot["courses"] ?? []
        var rawCourses: [[String: Any]] = []
        collectCourses(from: rawRoot, into: &rawCourses)

        var seen = Set<String>()
        var courses = rawCourses.compactMap(parseCourse).filter { seen.insert($0.id).inserted }
        courses = ScheduleLogic.applyingExamWeeks(to: courses)
        courses.sort {
            ($0.weekday, $0.startSlot, $0.name) < ($1.weekday, $1.startSlot, $1.name)
        }
        return ScheduleSnapshot(
            termID: termID,
            termStartDate: termStartDate,
            fetchedAt: ISO8601DateFormatter().string(from: fetchedAt),
            courses: courses
        )
    }

    private static func collectCourses(from value: Any, into output: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            if dictionary["courseName"] != nil || dictionary["jx0408id"] != nil {
                output.append(dictionary)
                return
            }
            for child in dictionary.values { collectCourses(from: child, into: &output) }
        } else if let array = value as? [Any] {
            for child in array { collectCourses(from: child, into: &output) }
        }
    }

    private static func parseCourse(_ raw: [String: Any]) -> Course? {
        guard let (startSlot, endSlot) = slots(from: raw) else { return nil }
        let weekdayText = SJDScheduleClient.string(raw["weekDay"]).nilIfEmpty
            ?? SJDScheduleClient.string(raw["classTime"])
        guard
            let first = weekdayText.first,
            let weekday = first.wholeNumberValue,
            (1...7).contains(weekday)
        else { return nil }

        let name = SJDScheduleClient.string(raw["courseName"])
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未命名课程"
        let teacher = SJDScheduleClient.string(raw["teacherName"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let building = SJDScheduleClient.string(raw["buildingName"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let room = [raw["classroomName"], raw["location"]]
            .map(SJDScheduleClient.string)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location: String
        if !building.isEmpty, !room.isEmpty, !room.contains(building) {
            location = "\(building)-\(room)"
        } else {
            location = room.isEmpty ? building : room
        }
        let weekText = [raw["classWeek"], raw["classWeekDetails"]]
            .map(SJDScheduleClient.string)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let weeks = weekNumbers(from: raw)
        let stable = [
            SJDScheduleClient.string(raw["jx0408id"]), name, teacher, location, weekText,
            String(weekday), String(startSlot), String(endSlot)
        ].joined(separator: "|")
        let digest = Insecure.SHA1.hash(data: Data(stable.utf8))
        let id = digest.map { String(format: "%02x", $0) }.joined().prefix(12)
        let startTime = SJDScheduleClient.string(raw["startTime"]).nilIfEmpty
            ?? SlotMetadata.defaults[startSlot].start
        let endTime = SJDScheduleClient.string(raw["endTIme"]).nilIfEmpty
            ?? SJDScheduleClient.string(raw["endTime"]).nilIfEmpty
            ?? SlotMetadata.defaults[endSlot].end

        return Course(
            id: String(id),
            name: name,
            teacher: teacher,
            room: location,
            weekText: weekText,
            weekNumbers: weeks,
            examWeekNumbers: [],
            weekday: weekday,
            startSlot: startSlot,
            endSlot: endSlot,
            sectionText: "\(startSlot + 1)-\(endSlot + 1)节",
            timeRange: "\(startTime)-\(endTime)"
        )
    }

    private static func weekNumbers(from raw: [String: Any]) -> [Int] {
        let details = SJDScheduleClient.string(raw["classWeekDetails"])
        let explicit = integerMatches(in: details)
        if !explicit.isEmpty { return Array(Set(explicit)).sorted() }

        let text = SJDScheduleClient.string(raw["classWeek"])
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: " ", with: "")
        let odd = text.contains("单")
        let even = text.contains("双")
        var weeks: [Int] = []
        for item in text.replacingOccurrences(of: "，", with: ",").split(separator: ",") {
            let numbers = integerMatches(in: String(item))
            if numbers.count >= 2 {
                weeks.append(contentsOf: numbers[0]...numbers[1])
            } else if let number = numbers.first {
                weeks.append(number)
            }
        }
        return Array(Set(weeks)).filter { (!odd || $0.isMultiple(of: 2) == false) && (!even || $0.isMultiple(of: 2)) }.sorted()
    }

    private static func slots(from raw: [String: Any]) -> (Int, Int)? {
        let classTime = String(SJDScheduleClient.string(raw["classTime"]).dropFirst())
        var nodes = matches(pattern: #"\d{2}"#, in: classTime).compactMap(Int.init)
        if nodes.isEmpty {
            nodes = integerMatches(in: SJDScheduleClient.string(raw["weekNoteDetail"]))
        }
        guard
            let minimum = nodes.min(), let maximum = nodes.max(),
            minimum >= 1, maximum <= SlotMetadata.defaults.count, minimum <= maximum
        else { return nil }
        return (minimum - 1, maximum - 1)
    }

    private static func inferTermStartDate(from root: [String: Any]) -> String? {
        let weekText = SJDScheduleClient.string(root["week"]).nilIfEmpty
            ?? ((root["topInfo"] as? [[String: Any]])?.first.map { SJDScheduleClient.string($0["week"]) })
        guard let week = weekText.flatMap(Int.init), week > 0 else { return nil }
        guard let dated = (root["date"] as? [[String: Any]])?.first(where: {
            $0["mxrq"] != nil && SJDScheduleClient.string($0["zc"]) != "all"
        }) else { return nil }
        guard let day = contractDate.date(from: SJDScheduleClient.string(dated["mxrq"])) else { return nil }
        let calendarWeekday = Calendar.shanghai.component(.weekday, from: day)
        let mondayBasedWeekday = ((calendarWeekday + 5) % 7) + 1
        let weekday = Int(SJDScheduleClient.string(dated["xqid"])) ?? mondayBasedWeekday
        guard
            let monday = Calendar.shanghai.date(byAdding: .day, value: -(weekday - 1), to: day),
            let termStart = Calendar.shanghai.date(byAdding: .day, value: -((week - 1) * 7), to: monday)
        else { return nil }
        return contractDate.string(from: termStart)
    }

    private static func integerMatches(in text: String) -> [Int] {
        matches(pattern: #"\d+"#, in: text).compactMap(Int.init)
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static let contractDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .shanghai
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
