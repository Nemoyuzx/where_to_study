import Foundation

struct CampusWeatherDay: Equatable, Sendable, Identifiable {
    let date: String
    let weekday: String
    let weatherDay: String
    let weatherNight: String
    let temperatureMaximum: Int
    let temperatureMinimum: Int
    let precipitationProbability: Int?

    var id: String { date }
}

struct CampusWeather: Equatable, Sendable {
    let campusID: String
    let campusName: String
    let district: String
    let currentWeather: String
    let currentTemperature: Int
    let reportTime: String
    let days: [CampusWeatherDay]
}

struct AlmanacInfo: Equatable, Sendable {
    let date: String
    let weekday: String
    let lunarDate: String
    let ganzhiYear: String
    let ganzhiMonth: String
    let ganzhiDay: String
    let zodiac: String
    let solarTerm: String?
    let lunarFestival: String?
    let solarFestival: String?
}

protocol DailyInfoFetching: Sendable {
    func fetchWeather(campusID: String) async throws -> CampusWeather
    func fetchAlmanac(date: String) async throws -> AlmanacInfo
}

enum DailyInfoError: LocalizedError, Equatable {
    case service(String)

    var errorDescription: String? {
        switch self {
        case let .service(message): message
        }
    }
}

enum DailyInfoLimits {
    static let maximumPayloadBytes = 128 * 1024
    static let source = "https://uapis.cn"
    static let sourceHost = "uapis.cn"
}

struct UAPIDailyInfoClient: DailyInfoFetching {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(
                configuration: configuration,
                delegate: DailyInfoRedirectDelegate(),
                delegateQueue: nil
            )
        }
    }

    func fetchWeather(campusID: String) async throws -> CampusWeather {
        let target = try Self.weatherTarget(campusID: campusID)
        let url = try Self.url(
            path: "/api/v1/misc/weather",
            queryItems: [
                URLQueryItem(name: "adcode", value: target.adcode),
                URLQueryItem(name: "lang", value: "zh"),
                URLQueryItem(name: "forecast", value: "true")
            ]
        )
        let data = try await fetch(url: url)
        return try Self.parseWeather(
            data: data,
            campusID: target.id,
            campusName: target.name
        )
    }

    func fetchAlmanac(date: String) async throws -> AlmanacInfo {
        guard let day = StrictContractDateParser.date(from: date) else {
            throw DailyInfoError.service("黄历日期格式不正确。")
        }
        guard let noon = Calendar.shanghai.date(byAdding: .hour, value: 12, to: day) else {
            throw DailyInfoError.service("无法换算黄历日期。")
        }
        let url = try Self.url(
            path: "/api/v1/misc/lunartime",
            queryItems: [
                URLQueryItem(name: "ts", value: String(Int(noon.timeIntervalSince1970))),
                URLQueryItem(name: "timezone", value: "Asia/Shanghai")
            ]
        )
        let data = try await fetch(url: url)
        return try Self.parseAlmanac(data: data, requestedDate: date)
    }

    private func fetch(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(HolidayUserAgent.value(), forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200 ... 299).contains(http.statusCode),
            response.url?.scheme == "https",
            response.url?.host == DailyInfoLimits.sourceHost
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DailyInfoError.service("生活信息接口返回错误，HTTP \(status)。")
        }
        guard
            response.expectedContentLength <= 0
                || response.expectedContentLength <= Int64(DailyInfoLimits.maximumPayloadBytes),
            data.count <= DailyInfoLimits.maximumPayloadBytes
        else {
            throw DailyInfoError.service("生活信息响应过大。")
        }
        return data
    }

    private static func weatherTarget(campusID: String) throws -> (id: String, name: String, adcode: String) {
        switch campusID.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "01", "1": ("01", "西土城", "110108")
        case "04", "4": ("04", "沙河", "110114")
        default: throw DailyInfoError.service("暂不支持该校区的天气查询。")
        }
    }

    private static func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(string: DailyInfoLimits.source)
        components?.path = path
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw DailyInfoError.service("生活信息接口地址不正确。")
        }
        return url
    }

    static func parseWeather(data: Data, campusID: String, campusName: String) throws -> CampusWeather {
        struct Source: Decodable {
            struct Day: Decodable {
                let date: String
                let week: String
                let tempMax: Double
                let tempMin: Double
                let weatherDay: String
                let weatherNight: String
                let pop: Double?

                enum CodingKeys: String, CodingKey {
                    case date, week, pop
                    case tempMax = "temp_max"
                    case tempMin = "temp_min"
                    case weatherDay = "weather_day"
                    case weatherNight = "weather_night"
                }
            }

            let district: String
            let weather: String
            let temperature: Double
            let reportTime: String
            let forecast: [Day]

            enum CodingKeys: String, CodingKey {
                case district, weather, temperature, forecast
                case reportTime = "report_time"
            }
        }

        let source: Source
        do {
            source = try JSONDecoder().decode(Source.self, from: data)
        } catch {
            throw DailyInfoError.service("天气数据格式不正确。")
        }
        guard
            !source.district.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !source.weather.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !source.reportTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            source.forecast.count >= 2
        else {
            throw DailyInfoError.service("天气数据缺少今日或明日信息。")
        }
        let days = try source.forecast.prefix(2).map { item -> CampusWeatherDay in
            guard StrictContractDateParser.date(from: item.date) != nil else {
                throw DailyInfoError.service("天气数据日期格式不正确。")
            }
            return CampusWeatherDay(
                date: item.date,
                weekday: item.week,
                weatherDay: item.weatherDay,
                weatherNight: item.weatherNight,
                temperatureMaximum: try roundedTemperature(item.tempMax),
                temperatureMinimum: try roundedTemperature(item.tempMin),
                precipitationProbability: try item.pop.map(roundedProbability)
            )
        }
        return CampusWeather(
            campusID: campusID,
            campusName: campusName,
            district: source.district,
            currentWeather: source.weather,
            currentTemperature: try roundedTemperature(source.temperature),
            reportTime: source.reportTime,
            days: days
        )
    }

    static func parseAlmanac(data: Data, requestedDate: String) throws -> AlmanacInfo {
        struct Source: Decodable {
            let datetime: String
            let weekday: String
            let lunarMonth: String
            let lunarDay: String
            let ganzhiYear: String
            let ganzhiMonth: String
            let ganzhiDay: String
            let zodiac: String
            let solarTerm: String?
            let lunarFestival: String?
            let solarFestival: String?

            enum CodingKeys: String, CodingKey {
                case datetime, zodiac
                case weekday = "weekday_cn"
                case lunarMonth = "lunar_month_cn"
                case lunarDay = "lunar_day_cn"
                case ganzhiYear = "ganzhi_year"
                case ganzhiMonth = "ganzhi_month"
                case ganzhiDay = "ganzhi_day"
                case solarTerm = "solar_term"
                case lunarFestival = "lunar_festival"
                case solarFestival = "solar_festival"
            }
        }

        guard StrictContractDateParser.date(from: requestedDate) != nil else {
            throw DailyInfoError.service("黄历日期格式不正确。")
        }
        let source: Source
        do {
            source = try JSONDecoder().decode(Source.self, from: data)
        } catch {
            throw DailyInfoError.service("黄历数据格式不正确。")
        }
        let required = [
            source.weekday, source.lunarMonth, source.lunarDay,
            source.ganzhiYear, source.ganzhiMonth, source.ganzhiDay, source.zodiac
        ]
        guard
            source.datetime.hasPrefix(requestedDate),
            required.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw DailyInfoError.service("黄历数据日期不一致或缺少必要字段。")
        }
        return AlmanacInfo(
            date: requestedDate,
            weekday: source.weekday,
            lunarDate: source.lunarMonth + source.lunarDay,
            ganzhiYear: source.ganzhiYear,
            ganzhiMonth: source.ganzhiMonth,
            ganzhiDay: source.ganzhiDay,
            zodiac: source.zodiac,
            solarTerm: source.solarTerm?.nilIfBlank,
            lunarFestival: source.lunarFestival?.nilIfBlank,
            solarFestival: source.solarFestival?.nilIfBlank
        )
    }

    private static func roundedTemperature(_ value: Double) throws -> Int {
        guard value.isFinite, (-150 ... 100).contains(value) else {
            throw DailyInfoError.service("天气温度超出合理范围。")
        }
        return Int(value.rounded())
    }

    private static func roundedProbability(_ value: Double) throws -> Int {
        guard value.isFinite, (0 ... 100).contains(value) else {
            throw DailyInfoError.service("天气降水概率超出合理范围。")
        }
        return Int(value.rounded())
    }
}

private final class DailyInfoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard
            request.url?.scheme == "https",
            request.url?.host == DailyInfoLimits.sourceHost
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

@MainActor
final class DailyInfoStore: ObservableObject {
    @Published private(set) var weatherByCampus = [String: CampusWeather]()
    @Published private(set) var weatherErrors = [String: String]()
    @Published private(set) var loadingWeatherCampuses = Set<String>()
    @Published private(set) var almanacByDate = [String: AlmanacInfo]()
    @Published private(set) var almanacErrors = [String: String]()
    @Published private(set) var loadingAlmanacDates = Set<String>()

    private let client: any DailyInfoFetching

    init(client: any DailyInfoFetching = UAPIDailyInfoClient()) {
        self.client = client
    }

    func loadWeather(campusID: String, sampleMode: Bool, force: Bool = false) async {
        guard force || weatherByCampus[campusID] == nil else { return }
        guard !loadingWeatherCampuses.contains(campusID) else { return }
        loadingWeatherCampuses.insert(campusID)
        weatherErrors.removeValue(forKey: campusID)
        defer { loadingWeatherCampuses.remove(campusID) }
        if sampleMode {
            weatherByCampus[campusID] = Self.sampleWeather(campusID: campusID)
            return
        }
        do {
            weatherByCampus[campusID] = try await client.fetchWeather(campusID: campusID)
        } catch {
            weatherErrors[campusID] = error.localizedDescription
        }
    }

    func loadAlmanac(date: String, sampleMode: Bool, force: Bool = false) async {
        guard force || almanacByDate[date] == nil else { return }
        guard !loadingAlmanacDates.contains(date) else { return }
        loadingAlmanacDates.insert(date)
        almanacErrors.removeValue(forKey: date)
        defer { loadingAlmanacDates.remove(date) }
        if sampleMode {
            almanacByDate[date] = Self.sampleAlmanac(date: date)
            return
        }
        do {
            almanacByDate[date] = try await client.fetchAlmanac(date: date)
        } catch {
            almanacErrors[date] = error.localizedDescription
        }
    }

    private static func sampleWeather(campusID: String) -> CampusWeather {
        let today = Date()
        let tomorrow = Calendar.shanghai.date(byAdding: .day, value: 1, to: today) ?? today
        let campus = campusID == "04" ? ("沙河", "昌平区") : ("西土城", "海淀区")
        return CampusWeather(
            campusID: campusID,
            campusName: campus.0,
            district: campus.1,
            currentWeather: "多云",
            currentTemperature: 27,
            reportTime: "示例数据",
            days: [
                CampusWeatherDay(date: StrictContractDateParser.string(from: today), weekday: "今天", weatherDay: "多云", weatherNight: "雷阵雨", temperatureMaximum: 32, temperatureMinimum: 23, precipitationProbability: 40),
                CampusWeatherDay(date: StrictContractDateParser.string(from: tomorrow), weekday: "明天", weatherDay: "晴", weatherNight: "多云", temperatureMaximum: 33, temperatureMinimum: 22, precipitationProbability: 10)
            ]
        )
    }

    private static func sampleAlmanac(date: String) -> AlmanacInfo {
        AlmanacInfo(date: date, weekday: "星期六", lunarDate: "七月初十", ganzhiYear: "丙午", ganzhiMonth: "丙申", ganzhiDay: "戊辰", zodiac: "马", solarTerm: nil, lunarFestival: nil, solarFestival: nil)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
