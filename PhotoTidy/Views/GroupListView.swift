import PhotoTidyCore
import SwiftUI

struct GroupListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = model.visibleGroups
        Group {
            if groups.isEmpty {
                ContentUnavailableView("정리할 묶음이 없어요", systemImage: "checkmark.circle")
            } else {
                List(groups) { group in
                    NavigationLink(value: group) {
                        HStack(spacing: 12) {
                            AssetImage(id: group.recommendedID, targetSize: CGSize(width: 240, height: 240))
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    Text("\(group.photos.count)")
                                        .font(.caption2.bold())
                                        .monospacedDigit()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.black.opacity(0.6), in: Capsule())
                                        .padding(4)
                                        .accessibilityHidden(true)
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("비슷한 사진 \(group.photos.count)장")
                                    .font(.headline)
                                Text(group.photos[0].item.takenAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("비슷한 사진 묶음")
        .navigationBarTitleDisplayMode(.inline)
    }
}
