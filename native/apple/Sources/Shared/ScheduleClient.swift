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

enum SJDResponseEndpoint: CaseIterable, Sendable {
    case login
    case curriculum
    case classrooms
}

enum SJDResponseLimits {
    static let maximumLoginBytes = 64 * 1024
    static let maximumCurriculumBytes = 2 * 1024 * 1024
    static let maximumClassroomsBytes = 2 * 1024 * 1024

    static func maximumBytes(for endpoint: SJDResponseEndpoint) -> Int {
        switch endpoint {
        case .login:
            maximumLoginBytes
        case .curriculum:
            maximumCurriculumBytes
        case .classrooms:
            maximumClassroomsBytes
        }
    }

    static func validate(_ data: Data, endpoint: SJDResponseEndpoint) throws {
        guard data.count <= maximumBytes(for: endpoint) else {
            throw oversizedResponseError(for: endpoint)
        }
    }

    static func oversizedResponseError(for endpoint: SJDResponseEndpoint) -> ScheduleClientError {
        let message = switch endpoint {
        case .login: "移动教务登录响应过大。"
        case .curriculum: "移动教务课表响应过大。"
        case .classrooms: "实时教室数据响应过大。"
        }
        return .invalidResponse(message)
    }
}

enum SJDNetworkPolicy {
    static let allowedScheme = "https"
    static let allowedHost = "jwglweixin.bupt.edu.cn"
    static let allowedPort = 443

    static func allows(_ url: URL?) -> Bool {
        guard
            let url,
            url.scheme?.lowercased() == allowedScheme,
            url.host?.lowercased() == allowedHost,
            url.user == nil,
            url.password == nil,
            effectivePort(of: url) == allowedPort
        else { return false }
        return true
    }

    static func allowsRedirect(from sourceURL: URL?, to destinationURL: URL?) -> Bool {
        guard
            allows(sourceURL),
            allows(destinationURL),
            let sourceURL,
            let destinationURL
        else { return false }
        return sourceURL.host?.lowercased() == destinationURL.host?.lowercased()
            && effectivePort(of: sourceURL) == effectivePort(of: destinationURL)
    }

    private static func effectivePort(of url: URL) -> Int? {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == allowedScheme ? allowedPort : nil
    }
}

final class SJDURLSessionRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let sourceURL = response.url ?? task.currentRequest?.url ?? task.originalRequest?.url
        completionHandler(
            SJDNetworkPolicy.allowsRedirect(from: sourceURL, to: request.url) ? request : nil
        )
    }
}

enum SJDURLSession {
    static let shared: URLSession = make()

    static func make(configuration: URLSessionConfiguration = .default) -> URLSession {
        URLSession(
            configuration: configuration,
            delegate: SJDURLSessionRedirectDelegate(),
            delegateQueue: nil
        )
    }
}

protocol SJDHTTPTransport: Sendable {
    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, URLResponse)
}

enum SJDHTTPTransportError: Error {
    case responseTooLarge
}

struct SJDURLSessionTransport: SJDHTTPTransport {
    let session: URLSession

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumBytes) {
            throw SJDHTTPTransportError.responseTooLarge
        }

        var data = Data()
        data.reserveCapacity(min(
            max(Int(response.expectedContentLength), 0),
            maximumBytes
        ))
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw SJDHTTPTransportError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, response)
    }
}

struct SJDScheduleClient: ScheduleFetching {
    private let api: SJDAPIClient

    init(session: URLSession = SJDURLSession.shared) {
        api = SJDAPIClient(session: session)
    }

    func fetch(
        credentials: Credentials,
        fallbackTermID: String,
        fallbackTermStartDate: String
    ) async throws -> ScheduleSnapshot {
        let token = try await api.login(credentials: credentials)
        async let currentRequest = api.curriculum(token: token, week: "")
        async let allRequest = api.curriculum(token: token, week: "all")
        let (currentData, allData) = try await (currentRequest, allRequest)
        return try SJDScheduleParser.parse(
            currentData: currentData,
            curriculumData: allData,
            fallbackTermID: fallbackTermID,
            fallbackTermStartDate: fallbackTermStartDate
        )
    }

    fileprivate static func string(_ value: Any?) -> String {
        SJDAPIClient.string(value)
    }
}

enum SJDFormURLEncoder {
    static func data(_ values: [String: String]) -> Data {
        values.sorted { $0.key < $1.key }
            .map { "\(encodeComponent($0.key))=\(encodeComponent($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func encodeComponent(_ value: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var encoded = [UInt8]()
        encoded.reserveCapacity(value.utf8.count)

        for byte in value.utf8 {
            switch byte {
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x30 ... 0x39, 0x2A, 0x2D, 0x2E, 0x5F:
                encoded.append(byte)
            case 0x20:
                encoded.append(0x2B)
            default:
                encoded.append(0x25)
                encoded.append(hex[Int(byte >> 4)])
                encoded.append(hex[Int(byte & 0x0F)])
            }
        }
        return String(decoding: encoded, as: UTF8.self)
    }
}

struct SJDAPIClient: Sendable {
    static let origin = "https://jwglweixin.bupt.edu.cn"
    static let loginReferer = "\(origin)/sjd/#/login"
    static let classroomReferer = "\(origin)/sjd/#/restClassroom"

    private static let loginURL = URL(string: "\(origin)/bjyddx/login")!
    private static let curriculumURL = URL(string: "\(origin)/bjyddx/student/curriculum")!
    private static let classroomsURL = URL(string: "\(origin)/bjyddx/todayClassrooms")!
    private let transport: any SJDHTTPTransport

    init(session: URLSession = SJDURLSession.shared) {
        transport = SJDURLSessionTransport(session: session)
    }

    init(transport: any SJDHTTPTransport) {
        self.transport = transport
    }

    func login(credentials: Credentials) async throws -> String {
        let account = credentials.account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, !credentials.password.isEmpty else {
            throw ScheduleClientError.missingCredentials
        }
        var request = URLRequest(url: Self.loginURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = SJDFormURLEncoder.data(["userNo": account, "pwd": credentials.password])
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

    func curriculum(token: String, week: String) async throws -> Data {
        var components = URLComponents(url: Self.curriculumURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "week", value: week)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        applyHeaders(to: &request, referer: Self.classroomReferer, token: token)

        let (data, response) = try await responseData(for: request, endpoint: .curriculum)
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

    func classrooms(token: String, campusID: String) async throws -> Data {
        var components = URLComponents(url: Self.classroomsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "campusId", value: campusID)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        applyHeaders(to: &request, referer: Self.classroomReferer, token: token)

        let (data, response) = try await responseData(for: request, endpoint: .classrooms)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw ScheduleClientError.service("实时教室数据获取失败，请稍后重试。")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScheduleClientError.invalidResponse("实时教室服务返回了无法识别的数据。")
        }
        guard Self.isSuccessful(payload) else {
            throw ScheduleClientError.service(
                Self.message(in: payload, fallback: "实时教室数据获取失败。")
            )
        }
        return data
    }

    private func responseObject(for request: URLRequest, failureMessage: String) async throws -> [String: Any] {
        do {
            let (data, response) = try await responseData(for: request, endpoint: .login)
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

    private func responseData(
        for request: URLRequest,
        endpoint: SJDResponseEndpoint
    ) async throws -> (Data, URLResponse) {
        guard SJDNetworkPolicy.allows(request.url) else {
            throw ScheduleClientError.invalidResponse("移动教务请求地址不符合安全策略。")
        }
        let maximumBytes = SJDResponseLimits.maximumBytes(for: endpoint)
        let result: (Data, URLResponse)
        do {
            result = try await transport.data(for: request, maximumBytes: maximumBytes)
        } catch SJDHTTPTransportError.responseTooLarge {
            throw SJDResponseLimits.oversizedResponseError(for: endpoint)
        }
        try SJDResponseLimits.validate(result.0, endpoint: endpoint)
        return result
    }

    private func applyHeaders(to request: inout URLRequest, referer: String, token: String?) {
        request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue(token, forHTTPHeaderField: "token") }
    }

    static func isSuccessful(_ payload: [String: Any]) -> Bool {
        string(payload["code"]) == "1"
    }

    static func message(in payload: [String: Any], fallback: String) -> String {
        string(payload["Msg"]).nilIfEmpty ?? string(payload["msg"]).nilIfEmpty ?? fallback
    }

    static func string(_ value: Any?) -> String {
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

        let topInfo = currentRoot["topInfo"] as? [[String: Any]] ?? []
        let termID = ([currentRoot["semesterId"], currentRoot["xnxq01id"]]
            + topInfo.flatMap { [$0["semesterId"], $0["xnxq01id"]] })
            .map(SJDScheduleClient.string)
            .first(where: { !$0.isEmpty }) ?? fallbackTermID
        let termStartDate = inferTermStartDate(from: currentRoot) ?? fallbackTermStartDate
        let rawRoot = curriculumRoot["item"] ?? curriculumRoot["courses"] ?? []
        var rawCourses: [[String: Any]] = []
        collectCourses(from: rawRoot, into: &rawCourses)

        var seen = Set<String>()
        var courses = rawCourses.compactMap(parseCourse).filter { seen.insert($0.id).inserted }
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
        let rawRoom = [raw["classroomName"], raw["location"]]
            .map(SJDScheduleClient.string)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let room = normalizeCourseRoom(rawRoom)
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

    static func normalizeCourseRoom(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return normalized }
        let buildingPrefix = parts[0].hasPrefix("教") ? parts[0].dropFirst() : parts[0][...]
        guard
            buildingPrefix.count == 1,
            buildingPrefix.allSatisfy(\.isNumber),
            parts[1].count == 3,
            parts[1].allSatisfy(\.isNumber)
        else { return normalized }
        return String(parts[1])
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
                let lower = min(numbers[0], numbers[1])
                let upper = max(numbers[0], numbers[1])
                guard lower >= 1, upper <= 53 else { continue }
                weeks.append(contentsOf: lower...upper)
            } else if let number = numbers.first, (1...53).contains(number) {
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
        guard let dated = (root["date"] as? [[String: Any]])?.first(where: {
            $0["mxrq"] != nil && SJDScheduleClient.string($0["zc"]) != "all"
        }) else { return nil }
        let topInfo = root["topInfo"] as? [[String: Any]] ?? []
        let week = ([dated["zc"], root["week"]] + topInfo.map { $0["week"] })
            .map(SJDScheduleClient.string)
            .compactMap(Int.init)
            .first(where: { $0 >= 0 })
        // The current-week endpoint reports the week before classes as week 0.
        // With the formula below, its Monday is exactly seven days before the
        // first teaching-week Monday, so it still yields the real term start.
        guard let week else { return nil }
        guard let day = StrictContractDateParser.date(
            from: SJDScheduleClient.string(dated["mxrq"])
        ) else { return nil }
        let calendarWeekday = Calendar.shanghai.component(.weekday, from: day)
        let mondayBasedWeekday = ((calendarWeekday + 5) % 7) + 1
        let rawWeekday = Int(SJDScheduleClient.string(dated["xqid"]))
        let weekday: Int
        if let rawWeekday {
            weekday = switch rawWeekday {
            case 0: 7
            case 1 ... 7: rawWeekday
            default: mondayBasedWeekday
            }
        } else {
            weekday = mondayBasedWeekday
        }
        guard
            let monday = Calendar.shanghai.date(byAdding: .day, value: -(weekday - 1), to: day),
            let termStart = Calendar.shanghai.date(byAdding: .day, value: -((week - 1) * 7), to: monday)
        else { return nil }
        return StrictContractDateParser.string(from: termStart)
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

}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
