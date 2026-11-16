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
    @State private var renaming: TimelineStop?
    @State private var newName = ""
    @State private var isPreparingShare = false
    @State private var shared: SharedFile?

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
                } else if case .album(let album) = model.source {
                    albumContent(album)
                } else if let day = model.day {
                    dayContent(day)
                } else {
                    ContentUnavailableView("사진이 없어요", systemImage: "photo")
                }
            }
            .navigationTitle("타임라인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hasAccess {
                    ToolbarItem(placement: .principal) {
                        sourceMenu
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        shareButton
                    }
                }
            }
        }
        .task(id: hasAccess) {
            if hasAccess {
                await model.loadDays()
            }
        }
        .onChange(of: model.day) {
            camera = .automatic
        }
        .onChange(of: model.source) {
            camera = .automatic
        }
        .sheet(isPresented: $isPickingDate) {
            datePicker
        }
        .sheet(item: $shared) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .alert("장소 이름", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("이름", text: $newName)
            Button("저장") {
                if let stop = renaming {
                    model.rename(stop, to: newName)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("비워 두고 저장하면 자동으로 찾은 이름으로 돌아가요.")
        }
        .sheet(item: $viewing) { photo in
            AssetImage(id: photo.id, targetSize: CGSize(width: 1600, height: 1600), contentMode: .fit,
                       allowNetwork: isAlbum)
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

    @ViewBuilder
    private var shareButton: some View {
        if isPreparingShare {
            ProgressView()
        } else {
            Button {
                isPreparingShare = true
                Task {
                    if let url = await TimelineShare.makeFile(model: model, library: app.library) {
                        shared = SharedFile(url: url)
                    }
                    isPreparingShare = false
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(model.stops.isEmpty || model.isLoading)
            .accessibilityLabel("타임라인 공유")
        }
    }

    private var isAlbum: Bool {
        model.source != .daily
    }

    private var sourceMenu: some View {
        Menu {
            Button {
                model.showDaily()
            } label: {
                menuLabel("전체 사진 (하루씩)", selected: !isAlbum)
            }
            albumSection("공유 앨범", model.albums.filter(\.isShared))
            albumSection("내 앨범", model.albums.filter { !$0.isShared })
        } label: {
            HStack(spacing: 4) {
                Text(sourceTitle)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
            }
        }
        .accessibilityLabel("범위 선택")
    }

    private var sourceTitle: String {
        if case .album(let album) = model.source {
            return album.title
        }
        return "전체 사진"
    }

    @ViewBuilder
    private func albumSection(_ title: String, _ albums: [PhotoAlbum]) -> some View {
        if !albums.isEmpty {
            Section(title) {
                ForEach(albums) { album in
                    Button {
                        model.showAlbum(album)
                    } label: {
                        menuLabel("\(album.title) (\(album.count)장)", selected: model.source == .album(album))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func albumContent(_ album: PhotoAlbum) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.title3.bold())
                    Text(albumSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !pins.isEmpty {
                    map
                } else if !model.stops.isEmpty {
                    Text("이 앨범 사진에는 위치 정보가 없어 지도를 표시하지 못해요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if model.stops.isEmpty {
                    Text("이 앨범에는 사진이 없어요.")
                        .foregroundStyle(.secondary)
                }
                ForEach(numberedSections, id: \.section.id) { item in
                    HStack {
                        Text(item.section.day.formatted(dividerFormat))
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        VStack { Divider() }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(Array(item.section.stops.enumerated()), id: \.element.id) { index, stop in
                        stopRow(stop, number: item.offset + index + 1)
                    }
                }
            }
            .padding()
        }
    }

    /// 날짜별 묶음과, 그 앞까지의 머문 곳 수(번호를 앨범 전체에서 잇기 위해).
    private var numberedSections: [(section: TimelineDay, offset: Int)] {
        var offset = 0
        return model.sections.map { section in
            defer { offset += section.stops.count }
            return (section, offset)
        }
    }

    /// 앨범이 여러 해에 걸치면 날짜 구분 줄에 연도도 적는다.
    private var dividerFormat: Date.FormatStyle {
        let years = Set(model.sections.map { Calendar.current.component(.year, from: $0.day) })
        return years.count > 1 ? .dateTime.year().month().day().weekday() : .dateTime.month().day().weekday()
    }

    private var albumSummary: String {
        let count = model.stops.reduce(0) { $0 + $1.photos.count }
        guard let first = model.sections.first?.day, let last = model.sections.last?.day else {
            return "\(count)장"
        }
        let format = Date.FormatStyle.dateTime.year().month().day()
        let period = first == last ? first.formatted(format) : "\(first.formatted(format)) – \(last.formatted(format))"
        return "\(period) · \(count)장"
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
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                Button {
                    newName = model.customName(for: stop) ?? ""
                    renaming = stop
                } label: {
                    Image(systemName: "pencil")
                        .padding(8)
                }
                .accessibilityLabel("장소 이름 바꾸기")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(stop.photos) { photo in
                        Button {
                            viewing = photo
                        } label: {
                            AssetImage(id: photo.id, targetSize: CGSize(width: 200, height: 200),
                                       allowNetwork: isAlbum)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("사진 크게 보기")
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
