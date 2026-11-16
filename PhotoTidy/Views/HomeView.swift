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
            ScrollView {
                VStack(spacing: 16) {
                    switch model.access {
                    case .notDetermined:
                        hero("photo.on.rectangle.angled", "사진첩 접근이 필요해요",
                             "비슷한 사진을 찾으려면 사진첩 접근이 필요해요. 사진은 기기 밖으로 나가지 않습니다.")
                        bigButton("사진 접근 허용") {
                            Task { await model.requestAccess() }
                        }
                    case .denied:
                        hero("lock", "사진첩 접근이 꺼져 있어요", "설정에서 사진 접근을 허용해 주세요.")
                        bigButton("설정 열기") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    case .limited, .full:
                        analysis
                    }
                }
                .padding()
            }
            .background(Theme.background)
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
        if model.isAnalyzing {
            VStack(alignment: .leading, spacing: 12) {
                Label("사진을 분석하고 있어요", systemImage: "sparkles")
                    .font(.headline)
                ProgressView(value: Double(model.processed), total: Double(max(model.total, 1)))
                HStack {
                    Text("\(model.processed) / \(model.total)장 분석 중")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("취소") {
                        model.cancelAnalysis()
                    }
                }
            }
            .card()
        } else if model.hasAnalyzed {
            summary
            Button {
                model.startAnalysis()
            } label: {
                Label("새 사진 분석", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            hero("sparkles.rectangle.stack", "비슷한 사진 찾기",
                 "연달아 찍은 비슷한 사진을 묶고, 가장 잘 나온 한 장을 추천해 드려요.")
            bigButton("분석 시작") {
                model.startAnalysis()
            }
        }

        if model.access == .limited {
            Label("선택한 일부 사진만 분석합니다.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var summary: some View {
        let groups = model.visibleGroups
        if groups.isEmpty {
            hero("checkmark.circle", "정리할 묶음이 없어요", "비슷한 사진이 생기면 새 사진 분석으로 다시 찾아보세요.")
        } else {
            let size = ByteCountFormatter.string(fromByteCount: model.reclaimableBytes, countStyle: .file)
            VStack(alignment: .leading, spacing: 14) {
                Text("비슷한 사진 묶음 \(groups.count)개")
                    .font(.title2.bold())
                HStack(spacing: 12) {
                    stat("\(model.deletableCount)장", "지울 수 있는 사진", "trash")
                    stat("약 \(size)", "확보되는 용량", "internaldrive")
                }
                NavigationLink(value: Route.groupList) {
                    Text("묶음 보기")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .card()
        }
        if model.unreadable > 0 {
            Label("이미지를 불러오지 못해 건너뛴 사진 \(model.unreadable)장", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func hero(_ icon: String, _ title: String, _ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .card()
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func stat(_ value: String, _ caption: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
