import SwiftUI

/// 사진첩 사진 한 장을 불러와 보여 준다.
struct AssetImage: View {
    @Environment(AppModel.self) private var model
    let id: String
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: id) {
            for await loaded in model.library.displayImages(id: id, targetSize: targetSize) {
                image = loaded
            }
        }
    }
}
