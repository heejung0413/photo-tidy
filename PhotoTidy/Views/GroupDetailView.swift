import PhotoTidyCore
import SwiftUI

struct GroupDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let group: StoredGroup
    @State private var keep: Set<String>
    @State private var current: String
    @State private var isDeleting = false

    init(group: StoredGroup) {
        self.group = group
        _keep = State(initialValue: [group.recommendedID])
        _current = State(initialValue: group.recommendedID)
    }

    private var deleteCount: Int { group.photos.count - keep.count }

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $current) {
                ForEach(group.photos, id: \.item.id) { photo in
                    AssetImage(id: photo.item.id, targetSize: CGSize(width: 1200, height: 1200), contentMode: .fit)
                        .tag(photo.item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Button {
                if keep.contains(current) {
                    keep.remove(current)
                } else {
                    keep.insert(current)
                }
            } label: {
                Label(keep.contains(current) ? "남기는 사진" : "이 사진 남기기",
                      systemImage: keep.contains(current) ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.bordered)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.photos, id: \.item.id) { photo in
                        thumbnail(photo.item.id)
                    }
                }
                .padding(.horizontal)
            }

            Button("나머지 \(deleteCount)장 삭제", role: .destructive) {
                isDeleting = true
                Task {
                    let deleted = await model.delete(group: group, keeping: keep)
                    isDeleting = false
                    if deleted {
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(keep.isEmpty || deleteCount == 0 || isDeleting)

            Button("이 묶음 건너뛰기") {
                model.skip(group)
                dismiss()
            }
            .padding(.bottom)
        }
        .navigationTitle("\(group.photos.count)장 중 \(keep.count)장 남김")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func thumbnail(_ id: String) -> some View {
        Button {
            current = id
        } label: {
            AssetImage(id: id, targetSize: CGSize(width: 200, height: 200))
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if keep.contains(id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, .green)
                            .padding(3)
                    }
                }
                .overlay(alignment: .bottom) {
                    if id == group.recommendedID {
                        Text("추천")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .background(.yellow, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(3)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(id == current ? Color.accentColor : .clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
    }
}
