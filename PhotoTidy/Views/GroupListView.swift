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
                            AssetImage(id: group.recommendedID, targetSize: CGSize(width: 200, height: 200))
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(group.photos.count)장")
                                    .font(.headline)
                                Text(group.photos[0].item.takenAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("비슷한 사진 묶음")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: StoredGroup.self) { group in
            GroupDetailView(group: group)
        }
    }
}
