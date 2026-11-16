import PhotoTidyCore
import SwiftUI

/// 값으로 이동하는 화면. 묶음 상세는 StoredGroup 값으로 이동한다.
enum Route: Hashable {
    case groupList
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch model.access {
                case .notDetermined:
                    Text("비슷한 사진을 찾으려면 사진첩 접근이 필요해요. 사진은 기기 밖으로 나가지 않습니다.")
                        .multilineTextAlignment(.center)
                    Button("사진 접근 허용") {
                        Task { await model.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                case .denied:
                    Text("사진첩 접근이 꺼져 있어요. 설정에서 허용해 주세요.")
                        .multilineTextAlignment(.center)
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                case .limited, .full:
                    analysis
                }
            }
            .padding()
            .navigationTitle("Photo Tidy")
            .navigationDestination(for: Route.self) { _ in
                GroupListView()
            }
            .navigationDestination(for: StoredGroup.self) { group in
                GroupDetailView(group: group)
            }
        }
    }

    @ViewBuilder
    private var analysis: some View {
        if model.access == .limited {
            Text("선택한 일부 사진만 분석합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if model.isAnalyzing {
            ProgressView(value: Double(model.processed), total: Double(max(model.total, 1)))
            Text("\(model.processed) / \(model.total)장 분석 중")
                .monospacedDigit()
            Button("취소") {
                model.cancelAnalysis()
            }
        } else {
            if model.hasAnalyzed {
                summary
            }
            Button(model.hasAnalyzed ? "새 사진 분석" : "분석 시작") {
                model.startAnalysis()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var summary: some View {
        let groups = model.visibleGroups
        if groups.isEmpty {
            Text("정리할 묶음이 없어요.")
        } else {
            let size = ByteCountFormatter.string(fromByteCount: model.reclaimableBytes, countStyle: .file)
            Text("비슷한 사진 묶음 \(groups.count)개")
                .font(.title2.bold())
            Text("정리하면 \(model.deletableCount)장 · 약 \(size) 확보")
                .foregroundStyle(.secondary)
            NavigationLink("묶음 보기", value: Route.groupList)
            .buttonStyle(.bordered)
        }
        if model.unreadable > 0 {
            Text("이미지를 불러오지 못해 건너뛴 사진 \(model.unreadable)장")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
