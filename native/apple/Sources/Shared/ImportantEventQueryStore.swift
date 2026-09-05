import Foundation
import Combine

struct ImportantEventQueryKey: Equatable {
    let sampleMode: Bool
    let publicRevision: UInt64
    let favorites: [PublicDeadlineItem]
    let query: String
    let category: ImportantEventCategory
    let metadataCategory: String
    let showsEnded: Bool
    let minute: Int
}

struct ImportantEventQueryResult: Sendable {
    var totalCount = 0
    var categories: [ImportantEventCategory] = [.all]
    var category: ImportantEventCategory = .all
    var metadataCategories: [String] = []
    var metadataCategory = ""
    var items: [PublicDeadlineItem] = []
}

// Parsing, deduplication, sorting and search indexing belong to a data worker,
// never a SwiftUI body or its scroll/pagination invalidations.
actor ImportantEventQueryWorker {
    private struct IndexedEvent {
        let item: PublicDeadlineItem
        let deadline: Date?
        let searchText: String
    }

    private var indexedPublicRevision: UInt64?
    private var indexedFavorites: [PublicDeadlineItem] = []
    private var index: [IndexedEvent] = []
    private var categories: [ImportantEventCategory] = [.all]
    private(set) var indexBuildCount = 0

    func query(
        snapshots: [String: PublicDeadlineSnapshot],
        publicRevision: UInt64,
        favorites: [PublicDeadlineItem],
        query: String,
        category: ImportantEventCategory,
        metadataCategory: String,
        showsEnded: Bool,
        now: Date
    ) throws -> ImportantEventQueryResult {
        try Task.checkCancellation()
        if indexedPublicRevision != publicRevision || indexedFavorites != favorites {
            let items = ImportantEventQueryLogic.mergedItems(
                liveItems: snapshots.values.flatMap(\.items),
                favoriteItems: favorites
            )
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let seconds = ISO8601DateFormatter()
            seconds.formatOptions = [.withInternetDateTime]
            let nextIndex = try items.map { item in
                try Task.checkCancellation()
                let searchable = [
                    item.name, item.organizer ?? "", item.sourceName ?? "",
                    item.source.title, item.kind.title, item.deadline, item.level ?? "",
                    item.location ?? "", item.description ?? "", item.eligibility ?? "",
                    item.notes ?? "", item.metadataSource?.name ?? "",
                    item.metadataSource?.sourceType ?? "", item.status ?? "",
                    item.region ?? "", item.mode ?? ""
                ] + item.categories + item.tags
                return IndexedEvent(
                    item: item,
                    deadline: fractional.date(from: item.deadline) ?? seconds.date(from: item.deadline),
                    searchText: searchable.joined(separator: "\u{001F}").lowercased()
                )
            }
            index = nextIndex
            categories = ImportantEventQueryLogic.availableCategories(in: items)
            indexedPublicRevision = publicRevision
            indexedFavorites = favorites
            indexBuildCount += 1
        }
        let effectiveCategory = ImportantEventQueryLogic.normalizedCategory(
            category, availableCategories: categories
        )
        let scoped = try index.filter { entry in
            try Task.checkCancellation()
            return effectiveCategory.includes(entry.item)
                && (showsEnded || (!entry.item.archived && entry.deadline.map { $0 >= now } == true))
        }
        let metadata = Array(Set(scoped.flatMap(\.item.categories))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let effectiveMetadata = ImportantEventQueryLogic.normalizedMetadataCategory(
            metadataCategory, availableCategories: metadata
        )
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = try scoped.filter { entry in
            try Task.checkCancellation()
            return (effectiveMetadata.isEmpty || entry.item.categories.contains(effectiveMetadata))
                && (needle.isEmpty || entry.searchText.contains(needle))
        }.map(\.item)
        return ImportantEventQueryResult(
            totalCount: index.count, categories: categories, category: effectiveCategory,
            metadataCategories: metadata, metadataCategory: effectiveMetadata, items: result
        )
    }
}

@MainActor
final class ImportantEventQueryStore: ObservableObject {
    @Published private(set) var result = ImportantEventQueryResult()
    private let worker = ImportantEventQueryWorker()
    private var revision: UInt64 = 0
    private var completedKey: ImportantEventQueryKey?

    func update(key: ImportantEventQueryKey, snapshots: [String: PublicDeadlineSnapshot]) async {
        revision &+= 1
        // Returning to an already displayed filter must still invalidate a
        // different in-flight search (A -> B -> A).
        guard completedKey != key else { return }
        let requestRevision = revision
        do {
            let next = try await worker.query(
                snapshots: snapshots, publicRevision: key.publicRevision, favorites: key.favorites,
                query: key.query, category: key.category, metadataCategory: key.metadataCategory,
                showsEnded: key.showsEnded, now: .now
            )
            guard !Task.isCancelled, requestRevision == revision else { return }
            completedKey = key
            result = next
        } catch is CancellationError {
            // Keep the previous valid projection while the replacement search runs.
        } catch {
            assertionFailure("Unexpected event projection error: \(error)")
        }
    }
}
