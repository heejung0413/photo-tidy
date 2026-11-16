import MapKit
import PhotoTidyCore
import SwiftUI

struct TimelineView: View {
    @Environment(AppModel.self) private var app
    @Environment(TimelineModel.self) private var model

    @State private var camera: MapCameraPosition = .automatic
    @State private var isPickingDate = false
    @State private var pickedDate = Date()
    @State private var viewing: TimelinePhoto?

    private struct Pin: Identifiable {
        let id: String
        let number: Int
        let title: String
        let coordinate: CLLocationCoordinate2D
    }

    private var hasAccess: Bool {
        app.access == .full || app.access == .limited
    }

    private var pins: [Pin] {
        model.stops.enumerated().compactMap { index, stop in
            guard let center = stop.center else { return nil }
            let title = model.title(for: stop)
            // 이름이 늦게 도착해도 핀 글자가 바뀌도록 id에 제목을 포함한다.
            return Pin(id: "\(stop.id)|\(title)", number: index + 1, title: title,
                       coordinate: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAccess {
                    ContentUnavailableView("사진 접근이 필요해요", systemImage: "photo.on.rectangle",
                                           description: Text("정리 탭에서 사진 접근을 허용해 주세요."))
                } else if let day = model.day {
                    dayContent(day)
                } else {
                    ContentUnavailableView("사진이 없어요", systemImage: "photo")
                }
            }
            .navigationTitle("타임라인")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: hasAccess) {
            if hasAccess {
                await model.loadDays()
            }
        }
        .onChange(of: model.day) {
            camera = .automatic
        }
        .sheet(isPresented: $isPickingDate) {
            datePicker
        }
        .sheet(item: $viewing) { photo in
            AssetImage(id: photo.id, targetSize: CGSize(width: 1600, height: 1600), contentMode: .fit)
                .ignoresSafeArea()
        }
    }

    private func dayContent(_ day: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(day)
                if !pins.isEmpty {
                    map
                }
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(stop, number: index + 1)
                }
            }
            .padding()
        }
    }

    private func header(_ day: Date) -> some View {
        HStack {
            Button {
                if let previous = model.previousDay {
                    model.show(previous)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.previousDay == nil)
            .accessibilityLabel("이전 날")

            Spacer()
            Button(day.formatted(.dateTime.year().month().day().weekday())) {
                pickedDate = day
                isPickingDate = true
            }
            .font(.headline)
            Spacer()

            Button {
                if let next = model.nextDay {
                    model.show(next)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.nextDay == nil)
            .accessibilityLabel("다음 날")
        }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(pins) { pin in
                Marker(pin.title, monogram: Text("\(pin.number)"), coordinate: pin.coordinate)
            }
            MapPolyline(coordinates: pins.map(\.coordinate))
                .stroke(.blue, lineWidth: 3)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stopRow(_ stop: TimelineStop, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                focus(stop)
            } label: {
                HStack(spacing: 10) {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.blue, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title(for: stop))
                            .font(.headline)
                        Text("\(timeRange(stop)) · \(stop.photos.count)장")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(stop.photos) { photo in
                        Button {
                            viewing = photo
                        } label: {
                            AssetImage(id: photo.id, targetSize: CGSize(width: 200, height: 200))
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 72)
        }
    }

    private var datePicker: some View {
        NavigationStack {
            DatePicker("날짜", selection: $pickedDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("날짜 선택")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("보기") {
                            model.showNearest(to: pickedDate)
                            isPickingDate = false
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private func timeRange(_ stop: TimelineStop) -> String {
        let start = stop.start.formatted(date: .omitted, time: .shortened)
        let end = stop.end.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start)–\(end)"
    }

    private func focus(_ stop: TimelineStop) {
        guard let center = stop.center else { return }
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                latitudinalMeters: 600, longitudinalMeters: 600))
        }
    }
}
