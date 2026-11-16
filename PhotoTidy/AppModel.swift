import Foundation
import Observation
import Photos
import PhotoTidyCore

@MainActor
@Observable
final class AppModel {
    enum Access {
        case notDetermined, denied, limited, full
    }

    private(set) var access: Access = .notDetermined
    private(set) var isAnalyzing = false
    private(set) var processed = 0
    private(set) var total = 0
    private(set) var unreadable = 0
    private(set) var state: StoreState

    let library = PhotoLibrary()
    private let store: GroupStore
    private var task: Task<Void, Never>?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = GroupStore(url: directory.appendingPathComponent("groups.json"))
        state = store.load()
        refreshAccess()
    }

    var hasAnalyzed: Bool { state.watermark != nil }

    /// 숨기지 않은 묶음, 최신순.
    var visibleGroups: [StoredGroup] {
        state.groups
            .filter { !$0.isSkipped }
            .sorted { $0.photos[0].item.takenAt > $1.photos[0].item.takenAt }
    }

    /// 추천 한 장씩만 남길 때 지울 수 있는 장수.
    var deletableCount: Int {
        visibleGroups.reduce(0) { $0 + $1.photos.count - 1 }
    }

    /// 추천 한 장씩만 남길 때 확보되는 용량(어림).
    var reclaimableBytes: Int64 {
        let pixels = visibleGroups.reduce(0) { sum, group in
            sum + group.photos.filter { $0.item.id != group.recommendedID }.reduce(0) { $0 + $1.item.pixelCount }
        }
        return Int64(Double(pixels) * Tuning.estimatedBytesPerPixel)
    }

    func refreshAccess() {
        switch library.status {
        case .authorized: access = .full
        case .limited: access = .limited
        case .denied, .restricted: access = .denied
        case .notDetermined: access = .notDetermined
        @unknown default: access = .denied
        }
        if access == .full || access == .limited {
            let ids = state.groups.flatMap { $0.photos.map(\.item.id) }
            state.prune(existing: library.existingIDs(of: ids))
        }
    }

    func requestAccess() async {
        _ = await library.requestAccess()
        refreshAccess()
    }

    func startAnalysis() {
        guard !isAnalyzing, access == .full || access == .limited else { return }
        isAnalyzing = true
        processed = 0
        total = 0
        unreadable = 0
        let library = self.library
        let resumeDate = state.resumeDate

        task = Task {
            let segments = await Task.detached(priority: .userInitiated) {
                SimilarityGrouper.segments(library.fetchPhotos(after: resumeDate))
            }.value
            total = segments.reduce(0) { $0 + $1.count }
            var sinceSave = 0

            for segment in segments {
                if Task.isCancelled { break }
                if segment.count >= 2 {
                    let output = await Task.detached(priority: .userInitiated) {
                        SegmentProcessor.process(segment) { library.analysisImage(id: $0) }
                    }.value
                    state.merge(output.groups)
                    unreadable += output.unreadable
                }
                if let last = segment.last {
                    state.watermark = max(state.watermark ?? .distantPast, last.takenAt)
                }
                processed += segment.count
                sinceSave += segment.count
                if sinceSave >= 200 {
                    try? store.save(state)
                    sinceSave = 0
                }
            }
            try? store.save(state)
            isAnalyzing = false
        }
    }

    func cancelAnalysis() {
        task?.cancel()
    }

    /// keep에 없는 사진을 삭제한다. 사용자가 확인 창에서 취소하면 false.
    func delete(group: StoredGroup, keeping keep: Set<String>) async -> Bool {
        let ids = group.photos.map(\.item.id).filter { !keep.contains($0) }
        guard !keep.isEmpty, !ids.isEmpty else { return false }
        guard await library.delete(ids: ids) else { return false }
        state.resolve(groupID: group.id, deleted: Set(ids))
        try? store.save(state)
        return true
    }

    func skip(_ group: StoredGroup) {
        state.skip(groupID: group.id)
        try? store.save(state)
    }
}
