import Darwin
import SwiftUI

struct HomeWidgetLayer: View {
    let widgets: [InstalledAppRecord]
    let canvasSize: CGSize

    @AppStorage("geeagent.home.widget.positions") private var storedPositions = "{}"
    @State private var dragTranslations: [String: CGSize] = [:]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(widgets) { widget in
                widgetView(for: widget)
                    .frame(width: 230, height: 118)
                    .position(displayPosition(for: widget))
                    .gesture(dragGesture(for: widget))
                    .zIndex(dragTranslations[widget.id] == nil ? 1 : 5)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: widgets.map(\.id))
    }

    @ViewBuilder
    private func widgetView(for widget: InstalledAppRecord) -> some View {
        switch widget.id {
        case "btc.price":
            BTCPriceHomeWidget()
        case "system.monitor":
            SystemMonitorHomeWidget()
        default:
            GenericHomeWidget(app: widget)
        }
    }

    private func dragGesture(for widget: InstalledAppRecord) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragTranslations[widget.id] = value.translation
            }
            .onEnded { value in
                var positions = decodedPositions()
                let base = storedPosition(for: widget)
                let next = CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height)
                positions[widget.id] = WidgetPoint(clamped(next))
                storedPositions = encode(positions)
                dragTranslations[widget.id] = nil
            }
    }

    private func displayPosition(for widget: InstalledAppRecord) -> CGPoint {
        let base = storedPosition(for: widget)
        let translation = dragTranslations[widget.id] ?? .zero
        return clamped(CGPoint(x: base.x + translation.width, y: base.y + translation.height))
    }

    private func storedPosition(for widget: InstalledAppRecord) -> CGPoint {
        if let point = decodedPositions()[widget.id]?.cgPoint {
            return clamped(point)
        }
        return defaultPosition(for: widget)
    }

    private func defaultPosition(for widget: InstalledAppRecord) -> CGPoint {
        let y = min(max(canvasSize.height * 0.34, 190), canvasSize.height - 160)
        switch widget.id {
        case "btc.price":
            return clamped(CGPoint(x: min(max(canvasSize.width * 0.34, 280), canvasSize.width - 160), y: y))
        case "system.monitor":
            return clamped(CGPoint(x: min(max(canvasSize.width * 0.54, 530), canvasSize.width - 160), y: y + 18))
        default:
            return clamped(CGPoint(x: canvasSize.width * 0.44, y: y + 32))
        }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 128), max(canvasSize.width - 128, 128)),
            y: min(max(point.y, 92), max(canvasSize.height - 92, 92))
        )
    }

    private func decodedPositions() -> [String: WidgetPoint] {
        guard let data = storedPositions.data(using: .utf8),
              let positions = try? JSONDecoder().decode([String: WidgetPoint].self, from: data)
        else {
            return [:]
        }
        return positions
    }

    private func encode(_ positions: [String: WidgetPoint]) -> String {
        guard let data = try? JSONEncoder().encode(positions),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

private struct WidgetPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private struct BTCPriceHomeWidget: View {
    @StateObject private var model = BTCPriceWidgetModel()

    var body: some View {
        HomeGlassWidgetCard(accent: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    WidgetIcon(symbol: "bitcoinsign.circle.fill", tint: .orange)
                    Text("BTC Pulse")
                        .font(.geeDisplaySemibold(13))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    statusDot(model.isLive ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.priceText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.96))
                        .minimumScaleFactor(0.75)
                    Text(model.caption)
                        .font(.geeBodyMedium(11))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }
        }
        .task {
            await model.start()
        }
    }
}

@MainActor
private final class BTCPriceWidgetModel: ObservableObject {
    @Published var priceText = "$ --"
    @Published var caption = "Coinbase spot price"
    @Published var isLive = false

    private var didStart = false

    func start() async {
        guard !didStart else { return }
        didStart = true
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func refresh() async {
        do {
            let url = URL(string: "https://api.coinbase.com/v2/prices/BTC-USD/spot")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(CoinbaseSpotResponse.self, from: data)
            let value = Double(response.data.amount) ?? 0
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.maximumFractionDigits = 0
            priceText = formatter.string(from: NSNumber(value: value)) ?? "$ \(Int(value))"
            caption = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
            isLive = true
        } catch {
            caption = "Waiting for network"
            isLive = false
        }
    }
}

private struct CoinbaseSpotResponse: Decodable {
    struct Payload: Decodable {
        var amount: String
    }

    var data: Payload
}

private struct SystemMonitorHomeWidget: View {
    @StateObject private var model = SystemMonitorWidgetModel()

    var body: some View {
        HomeGlassWidgetCard(accent: .cyan) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    WidgetIcon(symbol: "cpu.fill", tint: .cyan)
                    Text("System Monitor")
                        .font(.geeDisplaySemibold(13))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    statusDot(.green)
                }

                HStack(spacing: 14) {
                    MetricRing(title: "CPU", valueText: model.cpuText, fraction: model.cpuFraction, tint: .cyan)
                    MetricRing(title: "MEM", valueText: model.memoryText, fraction: model.memoryFraction, tint: .green)
                }
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

@MainActor
private final class SystemMonitorWidgetModel: ObservableObject {
    @Published var cpuText = "--"
    @Published var cpuFraction = 0.0
    @Published var memoryText = "--"
    @Published var memoryFraction = 0.0

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let sample = SystemMonitorSampler.sample()
                await MainActor.run {
                    self?.cpuFraction = sample.cpuFraction
                    self?.cpuText = "\(Int(sample.cpuFraction * 100))%"
                    self?.memoryFraction = sample.memoryFraction
                    self?.memoryText = "\(Int(sample.memoryFraction * 100))%"
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

private enum SystemMonitorSampler {
    static func sample() -> (cpuFraction: Double, memoryFraction: Double) {
        var load = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&load, Int32(load.count))
        let cpuCount = max(ProcessInfo.processInfo.processorCount, 1)
        let cpuFraction = loadCount > 0 ? min(max(load[0] / Double(cpuCount), 0), 1) : 0

        let memoryFraction = sampleMemoryFraction()
        return (cpuFraction, memoryFraction)
    }

    private static func sampleMemoryFraction() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let usedPages = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else {
            return 0
        }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

private struct GenericHomeWidget: View {
    let app: InstalledAppRecord

    var body: some View {
        HomeGlassWidgetCard(accent: .white) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetIcon(symbol: app.gearKind.systemImage, tint: .white)
                Text(app.name)
                    .font(.geeDisplaySemibold(14))
                    .foregroundStyle(.white.opacity(0.9))
                Text(app.summary)
                    .font(.geeBody(11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
    }
}

private struct HomeGlassWidgetCard<Content: View>: View {
    let accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassCard(cornerRadius: 20, darken: 0.13, materialOpacity: 0.58)
            .overlay(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.36))
                    .frame(width: 64, height: 2)
                    .padding(.top, 1)
            }
            .shadow(color: accent.opacity(0.14), radius: 18, x: 0, y: 8)
            .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 10)
    }
}

private struct WidgetIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint.opacity(0.95))
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.13), in: Circle())
    }
}

private struct MetricRing: View {
    let title: String
    let valueText: String
    let fraction: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint.opacity(0.86), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.geeDisplaySemibold(10))
                    .foregroundStyle(.white.opacity(0.42))
                Text(valueText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

private func statusDot(_ color: Color) -> some View {
    Circle()
        .fill(color.opacity(0.9))
        .frame(width: 7, height: 7)
        .shadow(color: color.opacity(0.72), radius: 6)
}
