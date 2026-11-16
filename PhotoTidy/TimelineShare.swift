import MapKit
import PhotoTidyCore
import SwiftUI

/// 지금 보고 있는 타임라인을 이미지 한 장으로 만든다.
@MainActor
enum TimelineShare {
    /// 이미지가 지나치게 길어지지 않도록 담는 머문 곳 수.
    static let maxStops = 40
    static let thumbnailsPerStop = 4
    private static let width: CGFloat = 390

    struct Stop: Identifiable {
        let id: String
        let number: Int
        let title: String
        let detail: String
        let thumbnails: [UIImage]
        let moreCount: Int
    }

    struct Section: Identifiable {
        let id: Int
        let header: String?
        var stops: [Stop]
    }

    /// 이미지를 임시 폴더에 저장하고 그 위치를 돌려준다. 머문 곳이 없으면 nil.
    static func makeFile(model: TimelineModel, library: PhotoLibrary) async -> URL? {
        guard !model.stops.isEmpty else { return nil }
        let isAlbum = model.source != .daily
        let days = model.sections.isEmpty
            ? [TimelineDay(day: model.day ?? model.stops[0].start, stops: model.stops)]
            : model.sections

        var sections: [Section] = []
        var routes: [[(number: Int, coordinate: CLLocationCoordinate2D)]] = []
        var number = 0
        for (index, day) in days.enumerated() where number < maxStops {
            var section = Section(
                id: index,
                header: isAlbum ? day.day.formatted(.dateTime.year().month().day().weekday()) : nil,
                stops: [])
            var route: [(number: Int, coordinate: CLLocationCoordinate2D)] = []
            for stop in day.stops where number < maxStops {
                number += 1
                var thumbnails: [UIImage] = []
                for photo in stop.photos.prefix(thumbnailsPerStop) {
                    var last: UIImage?
                    for await image in library.displayImages(id: photo.id, targetSize: CGSize(width: 240, height: 240),
                                                             allowNetwork: isAlbum) {
                        last = image
                    }
                    if let last {
                        thumbnails.append(last)
                    }
                }
                section.stops.append(Stop(id: stop.id, number: number, title: model.title(for: stop),
                                          detail: "\(timeRange(stop)) · \(stop.photos.count)장",
                                          thumbnails: thumbnails,
                                          moreCount: max(0, stop.photos.count - thumbnailsPerStop)))
                if let center = stop.center {
                    route.append((number, CLLocationCoordinate2D(latitude: center.latitude,
                                                                 longitude: center.longitude)))
                }
            }
            sections.append(section)
            routes.append(route)
        }

        let photoCount = model.stops.reduce(0) { $0 + $1.photos.count }
        let title: String
        var subtitle = "\(photoCount)장"
        if case .album(let album) = model.source {
            title = album.title
            if let first = days.first?.day, let last = days.last?.day {
                let format = Date.FormatStyle.dateTime.year().month().day()
                let period = first == last ? first.formatted(format)
                    : "\(first.formatted(format)) – \(last.formatted(format))"
                subtitle = "\(period) · \(photoCount)장"
            }
        } else {
            title = days[0].day.formatted(.dateTime.year().month().day().weekday())
        }

        let map = await mapImage(routes: routes, size: CGSize(width: width - 32, height: 230))
        let card = Card(title: title, subtitle: subtitle, map: map, sections: sections,
                        hiddenStops: model.stops.count - number)
            .frame(width: width)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let data = renderer.uiImage?.jpegData(compressionQuality: 0.9) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("타임라인.jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func timeRange(_ stop: TimelineStop) -> String {
        let start = stop.start.formatted(date: .omitted, time: .shortened)
        let end = stop.end.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start)–\(end)"
    }

    /// 번호 핀과 날짜별 경로 선을 그린 지도 그림. 위치가 없거나 지도를 못 받으면 nil.
    private static func mapImage(routes: [[(number: Int, coordinate: CLLocationCoordinate2D)]],
                                 size: CGSize) async -> UIImage? {
        let all = routes.flatMap { $0 }
        guard let first = all.first else { return nil }
        var rect = MKMapRect.null
        for pin in all {
            let point = MKMapPoint(pin.coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        // 핀이 가장자리에 붙지 않게 여백을 두고, 한 곳뿐이어도 최소 300m는 보이게 한다.
        let padding = max(rect.width, rect.height) * 0.25
            + 300 * MKMapPointsPerMeterAtLatitude(first.coordinate.latitude)
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect.insetBy(dx: -padding, dy: -padding)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let accent = UIColor(Theme.accent)
        return UIGraphicsImageRenderer(size: size).image { _ in
            snapshot.image.draw(at: .zero)
            accent.setStroke()
            for route in routes where route.count > 1 {
                let path = UIBezierPath()
                path.lineWidth = 3
                path.lineJoinStyle = .round
                path.move(to: snapshot.point(for: route[0].coordinate))
                for pin in route.dropFirst() {
                    path.addLine(to: snapshot.point(for: pin.coordinate))
                }
                path.stroke()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.white,
            ]
            for pin in all {
                let center = snapshot.point(for: pin.coordinate)
                let circle = UIBezierPath(ovalIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22))
                accent.setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2
                circle.stroke()
                let text = "\(pin.number)" as NSString
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
                          withAttributes: attributes)
            }
        }
    }

    private struct Card: View {
        let title: String
        let subtitle: String
        let map: UIImage?
        let sections: [Section]
        let hiddenStops: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let map {
                    Image(uiImage: map)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                ForEach(sections) { section in
                    if let header = section.header {
                        Text(header)
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    ForEach(section.stops) { stop in
                        row(stop)
                    }
                }
                if hiddenStops > 0 {
                    Text("외 \(hiddenStops)곳")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Photo Tidy")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .foregroundStyle(.black)
            .background(.white)
        }

        private func row(_ stop: Stop) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("\(stop.number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title)
                            .font(.headline)
                        Text(stop.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(Array(stop.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if stop.moreCount > 0 {
                        Text("+\(stop.moreCount)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// 시스템 공유 창.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
