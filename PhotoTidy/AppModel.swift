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
                if segment.count >= 2 {
                    let output = await Task.detached(priority: .userInitiated) {
                        SegmentProcessor.process(segment) { library.analysisImage(id: $0) }
                    }.value
                    state.merge(output.groups)
                    unreadable += output.unreadable
                    // 읽지 못한 사진은 분석 완료로 치지 않아 다음에 다시 시도한다.
                    let failed = Set(output.unreadableIDs)
                    state.markAnalyzed(segment.map(\.id).filter { !failed.contains($0) })
                } else {
                    state.markAnalyzed(segment.map(\.id))
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
