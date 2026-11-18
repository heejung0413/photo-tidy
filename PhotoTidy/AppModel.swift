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

    var hasAnalyzed: Bool { state.hasAnalyzed }

    /// 숨기지 않은 묶음, 최신순.
    var visibleGroups: [StoredGroup] { state.visibleGroups }

    /// 추천 한 장씩만 남길 때 지울 수 있는 장수.
    var deletableCount: Int { state.deletableCount }

    /// 추천 한 장씩만 남길 때 확보되는 용량(어림).
    var reclaimableBytes: Int64 { state.reclaimableBytes }

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
        let analyzed = state.analyzedIDs

        task = Task {
            let (existing, segments) = await Task.detached(priority: .userInitiated) {
                let photos = library.fetchPhotos()
                return (Set(photos.map(\.id)), AnalysisPlanner.pendingSegments(photos, analyzed: analyzed))
            }.value
            state.forgetAnalyzed(notIn: existing)
            state.hasAnalyzed = true
            total = segments.reduce(0) { $0 + $1.count }
            var sinceSave = 0

            for segment in segments {
                if Task.isCancelled { break }
                let processedBefore = processed
                if segment.count >= 2 {
                    // 긴 구간도 사진마다 진행을 알리고, 취소하면 바로 멈춘다.
                    let base = processedBefore
                    let work = Task.detached(priority: .userInitiated) {
                        SegmentProcessor.process(
                            segment,
                            isCancelled: { Task.isCancelled },
                            onProgress: { count in
                                Task { @MainActor in self.processed = max(self.processed, base + count) }
                            },
                            loadImage: { library.analysisImage(id: $0) })
                    }
                    let output = await withTaskCancellationHandler {
                        await work.value
                    } onCancel: {
                        work.cancel()
                    }
                    // 도중에 멈춘 구간은 분석한 것으로 치지 않는다. 다음에 다시 본다.
                    if output.wasCancelled { break }
                    state.merge(output.groups)
                    unreadable += output.unreadable
                    // 읽지 못한 사진은 다음에 다시 시도하고, 여러 번 실패하면 포기한다.
                    let failed = Set(output.unreadableIDs)
                    state.markAnalyzed(segment.map(\.id).filter { !failed.contains($0) })
                    state.markUnreadable(output.unreadableIDs)
                } else {
                    state.markAnalyzed(segment.map(\.id))
                }
                processed = max(processed, processedBefore + segment.count)
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
        state.resolve(group, deleted: Set(ids))
        try? store.save(state)
        return true
    }

    func skip(_ group: StoredGroup) {
        state.skip(group)
        try? store.save(state)
    }
}
