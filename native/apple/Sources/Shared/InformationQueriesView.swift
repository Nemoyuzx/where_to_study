import SwiftUI

enum InformationQueryMode: String, CaseIterable, Identifiable {
    case shuttle
    case importantEvents

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .shuttle: "班车查询"
        case .importantEvents: "重要事件"
        }
    }
}

enum ImportantEventCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case schoolNotice
    case competition
    case conference
    case journalSpecialIssue
    case summerCamp
    case hackathon
    case preAdmission

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: "全部"
        case .schoolNotice: "校内通知"
        case .competition: PublicDeadlineKind.competition.title
        case .conference: PublicDeadlineKind.conference.title
        case .journalSpecialIssue: PublicDeadlineKind.journalSpecialIssue.title
        case .summerCamp: PublicDeadlineKind.summerCamp.title
        case .hackathon: PublicDeadlineKind.hackathon.title
        case .preAdmission: PublicDeadlineKind.preAdmission.title
        }
    }

    func includes(_ item: PublicDeadlineItem) -> Bool {
        switch self {
        case .all: true
        case .schoolNotice: item.source == .schoolNotice
        case .competition: item.source != .schoolNotice && item.kind == .competition
        case .conference: item.source != .schoolNotice && item.kind == .conference
        case .journalSpecialIssue:
            item.source != .schoolNotice && item.kind == .journalSpecialIssue
        case .summerCamp: item.source != .schoolNotice && item.kind == .summerCamp
        case .hackathon: item.source != .schoolNotice && item.kind == .hackathon
        case .preAdmission: item.source != .schoolNotice && item.kind == .preAdmission
        }
    }
}

enum ImportantEventQueryLogic {
    static func mergedItems(
        liveItems: [PublicDeadlineItem],
        favoriteItems: [PublicDeadlineItem]
    ) -> [PublicDeadlineItem] {
        var seen = Set<String>()
        return (liveItems + favoriteItems)
            .filter { $0.source == .contestDDL || $0.source == .schoolNotice }
            .filter { seen.insert($0.favoriteID).inserted }
            .sorted { ($0.deadline, $0.name) < ($1.deadline, $1.name) }
    }

    static func filteredItems(
        _ items: [PublicDeadlineItem],
        query: String,
        category: ImportantEventCategory,
        metadataCategory: String = "",
        showsEnded: Bool = false,
        now: Date = .now
    ) -> [PublicDeadlineItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            guard category.includes(item) else { return false }
            guard metadataCategory.isEmpty || item.categories.contains(metadataCategory) else {
                return false
            }
            if !showsEnded, isEnded(item, now: now) { return false }
            guard !needle.isEmpty else { return true }
            return [
                item.name,
                item.organizer ?? "",
                item.sourceName ?? "",
                item.source.title,
                item.kind.title,
                item.deadline,
                item.level ?? "",
                item.location ?? "",
                item.description ?? "",
                item.eligibility ?? "",
                item.notes ?? "",
                item.metadataSource?.name ?? "",
                item.metadataSource?.sourceType ?? "",
                item.status ?? "",
                item.region ?? "",
                item.mode ?? "",
            ]
            .appending(contentsOf: item.categories)
            .appending(contentsOf: item.tags)
            .contains { $0.lowercased().contains(needle) }
        }
    }

    static func availableCategories(
        in items: [PublicDeadlineItem]
    ) -> [ImportantEventCategory] {
        ImportantEventCategory.allCases.filter { category in
            category == .all || items.contains(where: category.includes)
        }
    }

    static func metadataCategories(
        in items: [PublicDeadlineItem],
        category: ImportantEventCategory = .all,
        showsEnded: Bool = false,
        now: Date = .now
    ) -> [String] {
        let scopedItems = items.filter { item in
            category.includes(item) && (showsEnded || !isEnded(item, now: now))
        }
        return Array(Set(scopedItems.flatMap(\.categories))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func normalizedCategory(
        _ category: ImportantEventCategory,
        availableCategories: [ImportantEventCategory]
    ) -> ImportantEventCategory {
        availableCategories.contains(category) ? category : .all
    }

    static func normalizedMetadataCategory(
        _ category: String,
        availableCategories: [String]
    ) -> String {
        category.isEmpty || availableCategories.contains(category) ? category : ""
    }

    static func isEnded(_ item: PublicDeadlineItem, now: Date = .now) -> Bool {
        if item.archived { return true }
        guard let deadline = deadlineDate(item.deadline) else { return true }
        return deadline < now
    }

    private static func deadlineDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum ImportantEventIncrementalRendering {
    static let batchSize = 20
    static let preloadThreshold = 4

    static func visibleCount(totalCount: Int, requestedCount: Int) -> Int {
        min(max(0, requestedCount), max(0, totalCount))
    }

    static func shouldLoadNextBatch(
        appearingIndex: Int,
        visibleCount: Int,
        totalCount: Int
    ) -> Bool {
        guard visibleCount > 0, visibleCount < totalCount else { return false }
        return appearingIndex >= max(0, visibleCount - preloadThreshold)
    }

    static func nextRequestedCount(currentCount: Int, totalCount: Int) -> Int {
        min(max(0, totalCount), max(batchSize, currentCount + batchSize))
    }
}

private extension Array where Element == String {
    func appending(contentsOf values: [String]) -> [String] {
        self + values
    }
}

enum InformationQueryLoadSource: Hashable {
    case shuttle
    case importantEvents
}

enum InformationQueryLoadTrigger {
    case firstAppearance
    case modeSelection
    case manualShuttleRefresh
    case manualEventRefresh
}

enum InformationQueryLoadPolicy {
    static func sources(for trigger: InformationQueryLoadTrigger) -> Set<InformationQueryLoadSource> {
        switch trigger {
        case .firstAppearance: [.shuttle, .importantEvents]
        case .modeSelection: []
        case .manualShuttleRefresh: [.shuttle]
        case .manualEventRefresh: [.importantEvents]
        }
    }
}

@MainActor
enum InformationQueryPreloader {
    static func prewarm(
        shuttleStore: ShuttleBusStore,
        deadlineStore: CalendarDeadlineStore,
        sampleMode: Bool
    ) async {
        let sources = InformationQueryLoadPolicy.sources(for: .firstAppearance)
        guard sources.contains(.shuttle), sources.contains(.importantEvents) else { return }
        async let shuttleLoad: Void = shuttleStore.load(sampleMode: sampleMode)
        async let eventLoad: Void = deadlineStore.loadPublicQuery(sampleMode: sampleMode)
        _ = await (shuttleLoad, eventLoad)
    }
}

enum InformationQueryErrorLocalization {
    static func string(_ message: String, language: AppLanguage) -> String {
        let direct = AppLocalization.string(message, language: language)
        if direct != message { return direct }
        let knownPublicFeedFailure = [
            "主 DDL 数据源不可用",
            "备用数据源也不可用",
            "公开活动 DDL 不可用",
            "校内竞赛通知也不可用",
            "DDL 数据源返回错误",
        ].contains { message.contains($0) }
        if knownPublicFeedFailure {
            return AppLocalization.string(
                "无法同步公开活动或校内通知，请稍后重试。",
                language: language
            )
        }
        return message
    }
}

struct InformationQueriesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var calendarDeadlines: CalendarDeadlineStore
    @ObservedObject private var shuttleStore: ShuttleBusStore
    @ObservedObject private var eventQueryStore: ImportantEventQueryStore
    @State private var selectedMode: InformationQueryMode = .shuttle
    @State private var searchText = ""
    @State private var selectedCategory: ImportantEventCategory = .all
    @State private var selectedMetadataCategory = ""
    @State private var showsEndedEvents = false
    @State private var requestedVisibleEventCount = ImportantEventIncrementalRendering.batchSize

    init(shuttleStore: ShuttleBusStore, eventQueryStore: ImportantEventQueryStore) {
        self.shuttleStore = shuttleStore
        self.eventQueryStore = eventQueryStore
    }

    private var eventQueryKey: ImportantEventQueryKey {
        ImportantEventQueryKey(
            sampleMode: model.isSampleMode,
            publicRevision: calendarDeadlines.publicDataRevision,
            favorites: model.favoriteDeadlines, query: searchText,
            category: selectedCategory, metadataCategory: selectedMetadataCategory,
            showsEnded: showsEndedEvents, minute: Int(Date.now.timeIntervalSince1970 / 60)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageTitle(
                        eyebrow: "Where To Study",
                        title: "信息查询",
                        compact: proxy.size.height < 560
                    )
                    Picker("查询类型", selection: $selectedMode) {
                        ForEach(InformationQueryMode.allCases) { mode in
                            Text(model.localized(mode.titleKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("queries.mode")

                    switch selectedMode {
                    case .shuttle:
                        shuttleContent
                    case .importantEvents:
                        importantEventsContent
                    }
                }
                .padding(16)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
        .background(AppTheme.background)
        .navigationTitle(model.localized("信息查询"))
        .accessibilityIdentifier("screen.information-queries")
        .task(id: model.isSampleMode) {
            await InformationQueryPreloader.prewarm(
                shuttleStore: shuttleStore,
                deadlineStore: calendarDeadlines,
                sampleMode: model.isSampleMode
            )
        }
        .task(id: eventQueryKey) {
            await eventQueryStore.update(key: eventQueryKey, snapshots: calendarDeadlines.publicByDate)
        }
    }

    @ViewBuilder
    private var shuttleContent: some View {
        if shuttleStore.isLoading, shuttleStore.snapshot == nil {
            queryMessage(
                systemImage: "bus",
                title: "正在获取今日班车…",
                detail: "正在读取后勤部最新通知与当前生效时刻表。",
                showsProgress: true
            )
        } else if let snapshot = shuttleStore.snapshot {
            shuttleSnapshot(snapshot)
        } else {
            queryMessage(
                systemImage: "exclamationmark.triangle",
                title: "班车信息暂不可用",
                detail: shuttleStore.errorMessage,
                retry: { Task { await shuttleStore.load(force: true, sampleMode: model.isSampleMode) } }
            )
        }
    }

    private func shuttleSnapshot(_ snapshot: ShuttleBusSnapshot) -> some View {
        let now = Date()
        let schedules = ShuttleBusTodayLogic.activeSchedules(in: snapshot, on: now)
        let routes = schedules.map { schedule in
            (schedule, ShuttleBusTodayLogic.departures(for: schedule, on: now))
        }
        let departureCount = routes.reduce(0) { $0 + $1.1.count }
        let statusTitle = schedules.isEmpty
            ? "今日暂无生效班车时刻表"
            : departureCount == 0 ? "今日没有计划班次" : "今日班车按时刻表运行"
        let statusIcon = departureCount == 0 ? "calendar.badge.exclamationmark" : "bus.fill"

        return VStack(alignment: .leading, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: statusIcon)
                            .font(.title2)
                            .foregroundStyle(departureCount == 0 ? AppTheme.accent : AppTheme.primary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.localized(statusTitle))
                                .font(.headline)
                                .accessibilityIdentifier("queries.shuttle.status")
                            Text(model.localizedFormat("今日共 %lld 个方向、%lld 个计划班次", routes.count, departureCount))
                                .font(.callout)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Button {
                            Task { await shuttleStore.load(force: true, sampleMode: model.isSampleMode) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .disabled(shuttleStore.isLoading)
                        .accessibilityLabel("刷新班车信息")
                    }
                    if snapshot.status == "stale" {
                        Label("当前展示最近一次成功同步的缓存", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
                    if let notice = ShuttleBusTodayLogic.scheduleNotice(in: snapshot) {
                        Divider()
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(notice.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(model.localizedFormat("后勤部通知 · %@", notice.publishedAt))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer(minLength: 8)
                            if let url = notice.sourceURL {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .accessibilityLabel("查看班车通知原文")
                            }
                        }
                    }
                }
            }

            if routes.isEmpty {
                queryMessage(
                    systemImage: "calendar.badge.exclamationmark",
                    title: "今天没有处于有效期内的结构化班车表",
                    detail: "请查看后勤部最新通知，节假日及临时调整以后勤部原文为准。"
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 560), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(routes, id: \.0.id) { schedule, departures in
                        shuttleRouteCard(schedule: schedule, departures: departures, now: now)
                    }
                }
            }

            sourceNotice(
                text: "第三方来源：北京邮电大学后勤部公开通知，由 Where To Study 服务解析整理，仅供参考，请以官方原文为准。",
                url: snapshot.sourcePage
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queries.shuttle.snapshot")
        .accessibilityValue(snapshot.sourceName)
    }

    private func shuttleRouteCard(
        schedule: ShuttleBusSchedule,
        departures: [ShuttleBusDeparture],
        now: Date
    ) -> some View {
        let nowMinutes = Calendar.shanghai.component(.hour, from: now) * 60
            + Calendar.shanghai.component(.minute, from: now)
        let nextDeparture = departures.first { departure in
            timeMinutes(departure.departureTime).map { $0 > nowMinutes } ?? false
        }?.departureTime
        let periodText = schedule.period.startDate.map { start in
            schedule.period.endDate.map { "\(start) – \($0)" } ?? "\(start) 起"
        } ?? schedule.period.label
        return Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(AppTheme.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(schedule.from) → \(schedule.to)")
                            .font(.headline)
                        Text(periodText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                if departures.isEmpty {
                    Text("今天该方向暂无班次")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 86), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(departures) { departure in
                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(departure.departureTime)
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                    if departure.departureTime == nextDeparture {
                                        Circle().fill(AppTheme.primary).frame(width: 5, height: 5)
                                    }
                                }
                                Text("\(departure.service.vehicle) × \(departure.service.count)")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                departure.departureTime == nextDeparture
                                    ? AppTheme.primary.opacity(0.12)
                                    : AppTheme.background,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                }
            }
        }
    }

    private var importantEventsContent: some View {
        let projection = eventQueryStore.result
        let availableCategories = projection.categories
        let effectiveCategory = projection.category
        let metadataCategories = projection.metadataCategories
        let filtered = projection.items
        let visibleCount = ImportantEventIncrementalRendering.visibleCount(
            totalCount: filtered.count,
            requestedCount: requestedVisibleEventCount
        )
        let visibleItems = Array(filtered.prefix(visibleCount))

        return VStack(alignment: .leading, spacing: 14) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.secondaryText)
                        TextField("搜索名称、主办方或来源", text: $searchText)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清空搜索")
                        }
                    }
                    .padding(10)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.border, lineWidth: 1))

                    Text("事件类型")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(availableCategories) { category in
                                Button {
                                    AppHaptics.selection()
                                    if selectedCategory != category {
                                        selectedMetadataCategory = ""
                                    }
                                    selectedCategory = category
                                } label: {
                                    Text(model.localized(category.titleKey))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(
                                            effectiveCategory == category
                                                ? AppTheme.onPrimary
                                                : AppTheme.text
                                        )
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .background(
                                            effectiveCategory == category
                                                ? AppTheme.primaryFill
                                                : AppTheme.background,
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("queries.events.type.\(category.rawValue)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    if !metadataCategories.isEmpty {
                        Text("活动分类")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                metadataCategoryButton(title: "全部分类", value: "")
                                ForEach(metadataCategories, id: \.self) { category in
                                    metadataCategoryButton(title: category, value: category)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }

                    Toggle("显示已结束", isOn: $showsEndedEvents)
                        .toggleStyle(.switch)
                        .tint(AppTheme.primary)
                        .accessibilityIdentifier("queries.events.show-ended")

                    HStack {
                        Text(model.localizedFormat("按 DDL 升序 · %lld 项", filtered.count))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Button {
                            Task {
                                await calendarDeadlines.loadPublicQuery(
                                    sampleMode: model.isSampleMode,
                                    force: true
                                )
                            }
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(calendarDeadlines.isLoadingPublicFeed)
                    }
                }
            }

            if calendarDeadlines.isLoadingPublicFeed, projection.totalCount == 0 {
                queryMessage(
                    systemImage: "calendar.badge.clock",
                    title: "正在同步重要事件…",
                    detail: "正在读取公开活动与校内竞赛通知。",
                    showsProgress: true
                )
            } else if projection.totalCount == 0, !calendarDeadlines.publicFeedError.isEmpty {
                queryMessage(
                    systemImage: "exclamationmark.triangle",
                    title: "重要事件暂不可用",
                    detail: calendarDeadlines.publicFeedError,
                    retry: {
                        Task {
                            await calendarDeadlines.loadPublicQuery(
                                sampleMode: model.isSampleMode,
                                force: true
                            )
                        }
                    }
                )
            } else if filtered.isEmpty {
                queryMessage(
                    systemImage: "magnifyingglass",
                    title: "没有匹配的重要事件",
                    detail: "可尝试清空搜索词或切换分类。"
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.favoriteID) { index, item in
                        importantEventRow(item)
                            .onAppear {
                                loadMoreImportantEventsIfNeeded(
                                    appearingIndex: index,
                                    visibleCount: visibleItems.count,
                                    totalCount: filtered.count
                                )
                            }
                    }
                }
            }

            sourceNotice(
                text: "第三方来源：公开活动来自 Contest DDL（服务器提供备用接口）；校内竞赛通知由脚本从学校内部网站公开通知页提取整理。查询页不包含课程作业 DDL。",
                url: CalendarDeadlineSources.primaryPage
            )
        }
        .onChange(of: availableCategories) { categories in
            let normalized = ImportantEventQueryLogic.normalizedCategory(
                selectedCategory,
                availableCategories: categories
            )
            guard normalized != selectedCategory else { return }
            selectedCategory = normalized
            selectedMetadataCategory = ""
        }
        .onChange(of: metadataCategories) { categories in
            selectedMetadataCategory = ImportantEventQueryLogic.normalizedMetadataCategory(
                selectedMetadataCategory,
                availableCategories: categories
            )
        }
        .onChange(of: searchText) { _ in resetImportantEventRendering() }
        .onChange(of: selectedCategory) { _ in resetImportantEventRendering() }
        .onChange(of: selectedMetadataCategory) { _ in resetImportantEventRendering() }
        .onChange(of: showsEndedEvents) { _ in resetImportantEventRendering() }
    }

    private func resetImportantEventRendering() {
        requestedVisibleEventCount = ImportantEventIncrementalRendering.batchSize
    }

    private func loadMoreImportantEventsIfNeeded(
        appearingIndex: Int,
        visibleCount: Int,
        totalCount: Int
    ) {
        // Several rows near the boundary may appear in the same layout pass. Only the
        // first one is allowed to advance this page; later callbacks still carry the
        // old visibleCount and must not skip additional batches.
        guard requestedVisibleEventCount == visibleCount else { return }
        guard ImportantEventIncrementalRendering.shouldLoadNextBatch(
            appearingIndex: appearingIndex,
            visibleCount: visibleCount,
            totalCount: totalCount
        ) else { return }
        requestedVisibleEventCount = ImportantEventIncrementalRendering.nextRequestedCount(
            currentCount: requestedVisibleEventCount,
            totalCount: totalCount
        )
    }

    private func importantEventRow(_ item: PublicDeadlineItem) -> some View {
        let isFavorite = model.isFavorite(item)
        let tint = CalendarDeadlinePresentation.tint(for: item)
        return Surface {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(item.deadline.prefix(16)).replacingOccurrences(of: "T", with: " "))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(tint)
                    Text([
                        model.localized(item.source == .schoolNotice ? item.source.title : item.kind.title),
                        item.organizer,
                        item.metadataSource?.name,
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    let metadata = [
                        item.categories.joined(separator: " / "),
                        item.level,
                        item.location,
                    ].compactMap { value in
                        guard let value, !value.isEmpty else { return nil }
                        return value
                    }.joined(separator: " · ")
                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                VStack(spacing: 4) {
                    Button {
                        AppHaptics.selection()
                        model.setFavorite(item, isFavorite: !isFavorite)
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? AppTheme.accent : AppTheme.secondaryText)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFavorite ? "取消收藏" : "收藏日程")
                    if let url = item.officialURL {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("查看活动原文")
                    }
                }
            }
        }
        .accessibilityIdentifier("queries.event.\(item.source.rawValue).\(item.id)")
    }

    private func queryMessage(
        systemImage: String,
        title: String,
        detail: String,
        showsProgress: Bool = false,
        retry: (() -> Void)? = nil
    ) -> some View {
        Surface {
            VStack(spacing: 10) {
                if showsProgress {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Text(model.localized(title))
                    .font(.headline)
                if !detail.isEmpty {
                    Text(InformationQueryErrorLocalization.string(
                        detail,
                        language: model.appLanguage
                    ))
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                if let retry {
                    Button("重试", action: retry)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func sourceNotice(text: String, url: URL) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle")
                .foregroundStyle(AppTheme.primary)
            Text(model.localized(text))
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Link(destination: url) {
                Image(systemName: "arrow.up.right.square")
            }
            .accessibilityLabel("查看数据来源")
        }
        .padding(12)
        .background(AppTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metadataCategoryButton(title: String, value: String) -> some View {
        let selected = selectedMetadataCategory == value
        return Button {
            AppHaptics.selection()
            selectedMetadataCategory = value
        } label: {
            Text(model.localized(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? AppTheme.onPrimary : AppTheme.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(selected ? AppTheme.primaryFill : AppTheme.background, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("queries.events.category.\(value.isEmpty ? "all" : value)")
    }

    private func timeMinutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        return hour * 60 + minute
    }
}

struct InformationQueriesPresentation: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shuttleStore = ShuttleBusStore()
    @StateObject private var eventQueryStore = ImportantEventQueryStore()

    var body: some View {
        NavigationStack {
            InformationQueriesView(shuttleStore: shuttleStore, eventQueryStore: eventQueryStore)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 860, minHeight: 520, idealHeight: 720)
        #endif
    }
}
