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
    private var position: Int {
        (group.photos.firstIndex { $0.item.id == current } ?? 0) + 1
    }

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $current) {
                ForEach(group.photos, id: \.item.id) { photo in
                    AssetImage(id: photo.item.id, targetSize: CGSize(width: 1200, height: 1200), contentMode: .fit)
                        .tag(photo.item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(alignment: .top) {
                HStack {
                    if current == group.recommendedID {
                        Label("추천", systemImage: "star.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.yellow, in: Capsule())
                    }
                    Spacer()
                    Text("\(position) / \(group.photos.count)")
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(10)
            }
            .padding(.horizontal)

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
            .buttonBorderShape(.capsule)
            .tint(keep.contains(current) ? .green : Theme.accent)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.photos, id: \.item.id) { photo in
                        thumbnail(photo.item.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 3)
            }

            Button(role: .destructive) {
                isDeleting = true
                Task {
                    let deleted = await model.delete(group: group, keeping: keep)
                    isDeleting = false
                    if deleted {
                        dismiss()
                    }
                }
            } label: {
                Text("나머지 \(deleteCount)장 삭제")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .disabled(keep.isEmpty || deleteCount == 0 || isDeleting)

            Button("이 묶음 건너뛰기") {
                model.skip(group)
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.bottom)
        }
        .padding(.top, 8)
        .background(Theme.background)
        .navigationTitle("\(group.photos.count)장 중 \(keep.count)장 남김")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func thumbnail(_ id: String) -> some View {
        Button {
            current = id
        } label: {
            AssetImage(id: id, targetSize: CGSize(width: 200, height: 200))
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(keep.contains(id) ? 1 : 0.55)
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(id == current ? Color.accentColor : .clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
    }
}
