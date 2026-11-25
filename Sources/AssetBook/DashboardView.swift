import SwiftUI
import Charts

/// 總覽：淨資產與走勢 → 重點數字（總資產、負債、近期變動）→ 資產組成 → 市場
struct DashboardView: View {
    @Environment(\.portfolio) private var store
    @Binding var tab: AppTab
    @State private var mode: ValueMode = .live

    var body: some View {
        ScrollView {
            if let latest = store.latest {
                // 即時：最新紀錄 × 現在的報價，和最新紀錄比較；紀錄：最新紀錄，和前一筆比較
                let live = mode == .live
                let current = live ? (store.liveSnapshot ?? latest) : latest
                let comparison = live ? latest : store.snapshot(before: latest)
                VStack(spacing: 16) {
                    NetWorthCard(snapshot: current, record: latest, comparison: comparison, mode: $mode)
                    StatStrip(snapshot: current)
                    UpcomingBillsCard(record: latest)
                    CompositionCard(snapshot: current, previous: comparison, tab: $tab)
                    MarketCard(snapshot: current, previous: comparison)
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView {
                    Label("還沒有任何紀錄", systemImage: "tray")
                } description: {
                    Text("新增帳戶後，按「更新資產」記下第一筆數字。")
                } actions: {
                    Button("更新資產") { store.isUpdating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color.groupedBackground)
        .navigationTitle("總覽")
        // 切回總覽時，資料還新就不重抓；存了新紀錄或超過 5 分鐘才更新
        .task(id: store.latest?.id) {
            if store.isLiveStale || store.liveBaseID != store.latest?.id { await store.refreshLive() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if store.isLiveStale { await store.refreshLive() }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if mode == .live {
                    Button {
                        Task { await store.refreshLive() }
                    } label: {
                        Label("重新整理", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.liveStatus == .loading)
                    .help("重新取得即時報價與股價")
                }
                PrivacyToolbarButton(store: store)
                UpdateToolbarButton(store: store)
            }
        }
    }
}

enum ValueMode: Hashable { case live, record }

// MARK: - 淨資產＋走勢

/// 數字和走勢圖是一體的：拖過圖表時，上方的大數字即時變成那一天的淨值
private struct NetWorthCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let record: Snapshot
    let comparison: Snapshot?
    @Binding var mode: ValueMode

    @State private var range: TimeRange = .all
    @State private var selectedDate: Date?

    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "7天", month = "1個月", quarter = "3個月", year = "1年", all = "全部"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 31
            case .quarter: 92
            case .year: 366
            case .all: nil
            }
        }
    }

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
        var isLive = false
        /// 自動記錄的估值點（不是手動記錄）
        var isAuto = false
    }

    var body: some View {
        let pts = points
        let selected = selectedDate.flatMap { d in pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
        let net = store.netWorth(snapshot)
        let color = trendColor(pts)

        Card {
            HStack(alignment: .center) {
                status
                Spacer()
                Picker("顯示", selection: $mode) {
                    Text("即時").tag(ValueMode.live)
                    Text("\(record.date.formatted(.dateTime.month(.defaultDigits).day())) 紀錄").tag(ValueMode.record)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 6) {
                // 估算的數字前面加虛線圓圈：拖到估算的那天，或「即時」（最新紀錄 × 現在行情）
                let isEstimate = selected.map { $0.isAuto || $0.isLive } ?? (mode == .live && store.liveSnapshot != nil)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if isEstimate {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(.secondary)
                            .help("估算：餘額沿用最近一次記錄，股價和匯率用最新的")
                    }
                    MoneyText(value: selected?.value ?? net)
                }
                .font(.system(size: 48, weight: .regular))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                HStack(spacing: 8) {
                    if let selected, let first = pts.first {
                        // 拖曳中：和區間起點比較
                        DeltaBadge(delta: selected.value - first.value, base: first.value)
                        Text(selected.isLive ? "即時估算 vs 區間起點"
                             : "\(selected.date.formatted(.dateTime.year().month(.defaultDigits).day()))\(selected.isAuto ? " 估算" : "") vs 區間起點")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else if let comparison {
                        let old = store.netWorth(comparison)
                        DeltaBadge(delta: net - old, base: old)
                        Text("vs \(comparison.date.formatted(.dateTime.month(.defaultDigits).day()))\(mode == .live ? " 紀錄" : "")")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    staleReminder
                }
                .font(.subheadline)
            }

            chart(pts, selected: selected, color: color)
                .frame(height: 230)
                .padding(.top, 4)

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(TimeRange.allCases) { r in
                        let redundant = isRedundant(r)
                        Button {
                            withAnimation(.snappy) { range = r }
                        } label: {
                            Text(r.rawValue)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(range == r ? Color.primary.opacity(0.07) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .foregroundStyle(range == r ? AnyShapeStyle(.primary)
                                                 : redundant ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(redundant)
                        .help(redundant ? "紀錄還不到\(r.rawValue)，內容和「全部」相同" : "")
                    }
                }
                // 這個區間的漲跌：切換範圍時數字會跟著變
                if let first = pts.first, let last = pts.last, first.date != last.date {
                    HStack(spacing: 6) {
                        DeltaText(delta: last.value - first.value)
                        if first.value != 0 {
                            Text("(\(Fmt.percent((last.value - first.value) / abs(first.value))))")
                                .foregroundStyle(store.deltaColor(last.value - first.value))
                        }
                        Text("vs \(first.date.formatted(.dateTime.month(.defaultDigits).day()))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 紀錄的時間跨度（天）
    private var historyDays: Int {
        let all = store.chartSnapshots
        guard let first = all.first?.date, let last = all.last?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
    }

    /// 比紀錄還長、而且已經有較短的選項能涵蓋全部紀錄時，這個選項和「全部」完全一樣
    private func isRedundant(_ r: TimeRange) -> Bool {
        guard let days = r.days else { return false }
        let covering = TimeRange.allCases.compactMap(\.days).first { $0 >= historyDays }
        return covering.map { days > $0 } ?? false
    }

    // MARK: 狀態

    @ViewBuilder private var status: some View {
        Group {
            if mode == .record {
                Label("淨資產 · 紀錄", systemImage: "tray.full")
            } else {
                switch store.liveStatus {
                case .loading where store.liveUpdatedAt == nil:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("取得即時報價中") }
                case .failed where store.liveUpdatedAt == nil:
                    Label("無法取得即時報價，顯示紀錄數字", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                default:
                    Label {
                        Text("淨資產 · 即時估算 \((store.liveUpdatedAt ?? .now).formatted(date: .omitted, time: .shortened)) · 餘額沿用 \(record.date.formatted(.dateTime.month(.defaultDigits).day()))")
                    } icon: {
                        Circle().fill(.green).frame(width: 7, height: 7)
                    }
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    }

    /// 超過 7 天沒記錄才出現
    @ViewBuilder private var staleReminder: some View {
        let days = store.daysSinceLastUpdate ?? 0
        if days >= 7 {
            Button {
                store.isUpdating = true
            } label: {
                Label("\(days) 天沒記錄", systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("打開更新畫面，報價與股價會自動帶入")
        }
    }

    // MARK: 走勢圖

    /// 範圍內的紀錄；起點前一筆也帶進來，線才不會從中間開始
    private var points: [Point] {
        let all = store.chartSnapshots
        var inRange = all
        if let days = range.days, let end = all.last?.date,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: end) {
            inRange = all.filter { $0.date >= cutoff }
            if let before = all.last(where: { $0.date < cutoff }) { inRange.insert(before, at: 0) }
        }
        var p = inRange.map { Point(date: $0.date, value: store.netWorth($0), isAuto: store.isAuto($0)) }
        if mode == .live, let live = store.liveSnapshot {
            p.append(Point(date: live.date, value: store.netWorth(live), isLive: true))
        }
        return p
    }

    /// 走勢圖 X 軸：一年以上只標年份，兩個月以上標年/月，再短才標月/日
    static func axisLabel(_ d: Date, spanDays: Double) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        if spanDays > 400 { return "\(c.year!)" }
        if spanDays > 60 { return "\(c.year!)/\(c.month!)" }
        return "\(c.month!)/\(c.day!)"
    }

    /// 依區間漲跌決定線的顏色（跟隨紅漲綠跌設定）
    private func trendColor(_ pts: [Point]) -> Color {
        guard let a = pts.first?.value, let b = pts.last?.value, abs(b - a) >= 1 else { return .accentColor }
        return store.deltaColor(b - a)
    }

    private func chart(_ pts: [Point], selected: Point?, color: Color) -> some View {
        let recorded = pts.filter { !$0.isLive }
        let values = pts.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.2, hi * 0.005)
        let floor = lo - pad
        let last = pts.last

        return Chart {
            ForEach(recorded) { p in
                AreaMark(x: .value("日期", p.date), yStart: .value("下限", floor), yEnd: .value("淨值", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.14), color.opacity(0.0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("日期", p.date), y: .value("淨值", p.value), series: .value("系列", "紀錄"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                // 每個記錄日一個點：有記錄是實心點，估算是空心點
                if p.isAuto {
                    PointMark(x: .value("日期", p.date), y: .value("淨值", p.value))
                        .symbol {
                            Circle().strokeBorder(color, lineWidth: 1.5)
                                .background(Circle().fill(Color.cardBackground))
                                .frame(width: 7, height: 7)
                        }
                } else {
                    PointMark(x: .value("日期", p.date), y: .value("淨值", p.value))
                        .symbolSize(32)
                        .foregroundStyle(color)
                }
            }
            if let livePoint = pts.last, livePoint.isLive, let lastRecord = recorded.last {
                ForEach([lastRecord, livePoint]) { p in
                    LineMark(x: .value("日期", p.date), y: .value("淨值", p.value), series: .value("系列", "即時"))
                        .foregroundStyle(color.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
                }
            }
            if let last, selected == nil {
                PointMark(x: .value("日期", last.date), y: .value("淨值", last.value))
                    .symbolSize(44)
                    .foregroundStyle(color)
            }
            if let selected {
                RuleMark(x: .value("日期", selected.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("日期", selected.date), y: .value("淨值", selected.value))
                    .symbolSize(100)
                    .foregroundStyle(color)
            }
        }
        .chartYScale(domain: floor...(hi + pad))
        .chartXScale(range: .plotDimension(padding: 12))
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(store.hideAmounts ? "" : Fmt.wan(v)) }
                }
                .font(.caption2)
            }
        }
        .chartXAxis {
            // 跨年時刻度會落在 1/1，只顯示月/日會變成好幾個「1/1」：依區間長短換格式
            let span = (pts.last?.date ?? .now).timeIntervalSince(pts.first?.date ?? .now) / 86_400
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) { Text(Self.axisLabel(d, spanDays: span)) }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            }
        }
        .animation(.snappy, value: range)
    }
}

// MARK: - 一眼看完的數字

private struct StatStrip: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot

    var body: some View {
        let gross = store.grossAssets(snapshot)
        let debt = -store.total(.liability, in: snapshot)
        let net = store.netWorth(snapshot)
        // 約 30 天前的紀錄（沒有那麼久就用最早一筆）
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: snapshot.date) ?? snapshot.date
        let base = store.snapshots.last { $0.date <= cutoff } ?? store.snapshots.first

        let assets = tile("總資產") {
            MoneyText(value: gross)
        } footer: {
            Text("\(store.activeAccounts.filter { !$0.category.isLiability }.count) 個帳戶")
        }
        let liabilities = tile("負債") {
            OwedAmount(owed: debt)
        } footer: {
            Text(gross > 0 ? "佔總資產 \((debt / gross).formatted(.percent.precision(.fractionLength(1))))" : "—")
        }
        let change = tile(base.map { "自 \($0.date.formatted(.dateTime.month(.defaultDigits).day())) 以來" } ?? "近 30 天") {
                if let base, base.id != snapshot.id {
                    DeltaText(delta: net - store.netWorth(base))
                } else {
                    Text("—")
                }
            } footer: {
                if let base, base.id != snapshot.id {
                    let old = store.netWorth(base)
                    Text(old != 0 ? "\(Fmt.percent((net - old) / abs(old))) vs \(base.date.formatted(.dateTime.month(.defaultDigits).day()))" : "")
                }
            }

        // 寬螢幕：三張等寬一排；窄螢幕：總資產與負債並排，近期變動撐滿一排
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                assets.frame(minWidth: 200)
                liabilities.frame(minWidth: 200)
                change.frame(minWidth: 200)
            }
            VStack(spacing: 12) {
                HStack(spacing: 12) { assets; liabilities }
                change
            }
        }
    }

    /// 數字卡只放：標題、數字、說明，不加圖示
    private func tile<V: View, F: View>(_ title: String,
                                         @ViewBuilder value: () -> V, @ViewBuilder footer: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            value()
                .font(.system(size: 24, weight: .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 28, alignment: .leading)
            footer()
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - 資產組成

/// 動畫圓環圖＋圖例。滑過或點選某一塊，那一塊會變粗、其他變淡，中間顯示它的金額與佔比。
private struct CompositionCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?
    @Binding var tab: AppTab

    @State private var grouping: Grouping = .category
    @State private var selected: String?
    @State private var appeared = false

    enum Grouping: String, CaseIterable, Identifiable {
        case category = "分類", currency = "幣別"
        var id: Self { self }
    }

    private struct Part: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let color: Color
        let value: Double
        let previous: Double?
        let count: Int
        let category: AssetCategory?

        /// 現金那一塊：扣掉的負債（金額）與扣之前的存款，用在圖例的說明
        var deducted: Double = 0
        var gross: Double = 0

        var isLiabilityPart: Bool { category?.isLiability ?? false }

    }

    private var parts: [Part] {
        switch grouping {
        case .category:
            // 資產各類的佔比以總資產為 100%；負債另外列出（以應繳金額計），從總資產扣掉就是淨資產
            return AssetCategory.allCases.filter { !store.activeAccounts(in: $0).isEmpty }.map { c in
                let sign: Double = c.isLiability ? -1 : 1
                return Part(id: c.rawValue, title: c.title, symbol: c.symbol, color: c.tint,
                            value: max(sign * store.total(c, in: snapshot), 0),
                            previous: previous.map { sign * store.total(c, in: $0) },
                            count: store.activeAccounts(in: c).count, category: c)
            }
            .filter { $0.value > 0 || !$0.isLiabilityPart }
        case .currency:
            return Currency.allCases.map { c in
                Part(id: c.rawValue, title: c.name, symbol: currencySymbol(c), color: c.tint,
                     value: max(store.total(c, in: snapshot), 0),
                     previous: previous.map { store.total(c, in: $0) },
                     count: store.activeAccounts.filter { $0.currency == c && !$0.category.isLiability }.count,
                     category: nil)
            }
            .filter { $0.value > 0 } + liabilityPart
        }
    }

    /// 幣別分組時，負債併成一塊
    private var liabilityPart: [Part] {
        let c = AssetCategory.liability
        let debt = -store.total(c, in: snapshot)
        guard debt > 0 else { return [] }
        return [Part(id: c.rawValue, title: c.title, symbol: c.symbol, color: c.tint, value: debt,
                     previous: previous.map { -store.total(c, in: $0) },
                     count: store.activeAccounts(in: c).count, category: c)]
    }

    private func currencySymbol(_ c: Currency) -> String {
        switch c {
        case .twd: "dollarsign.circle.fill"
        case .usd: "dollarsign.square.fill"
        case .jpy: "yensign.circle.fill"
        case .gbp: "sterlingsign.circle.fill"
        }
    }

    var body: some View {
        let all = parts
        let assetParts = all.filter { !$0.isLiabilityPart }
        let debtPart = all.first { $0.isLiabilityPart }
        let assets = assetParts.reduce(0) { $0 + $1.value }
        let debt = debtPart?.value ?? 0

        Card {
            HStack(alignment: .center) {
                Text("資產組成").font(.headline.weight(.medium))
                if let d = previous?.date {
                    Text("漲跌 vs \(d.formatted(.dateTime.month(.defaultDigits).day()))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                Picker("分組", selection: $grouping) {
                    ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // 寬螢幕：圓環在左、圖例在右；窄螢幕：上下排列
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 36) {
                    donut(assetParts, debtPart: debtPart, assets: assets, debt: debt).frame(width: 230, height: 230)
                    legend(assetParts, debtPart: debtPart, assets: assets).frame(minWidth: 340)
                }
                VStack(spacing: 22) {
                    donut(assetParts, debtPart: debtPart, assets: assets, debt: debt).frame(width: 210, height: 210)
                    legend(assetParts, debtPart: debtPart, assets: assets)
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) { appeared = true }
        }
        .onChange(of: grouping) { _, _ in
            // 切換分組時重新播放動畫
            selected = nil
            appeared = false
            withAnimation(.easeOut(duration: 0.7)) { appeared = true }
        }
    }

    /// 圓環是資產組成（合計 = 總資產）；負債是現金那一塊裡面的細灰線。
    /// 中間預設顯示淨資產（總資產 − 負債）
    private func donut(_ assetParts: [Part], debtPart: Part?, assets: Double, debt: Double) -> some View {
        let shown = netParts(assetParts, debtPart: debtPart)
        let netTotal = max(shown.reduce(0) { $0 + max($1.value, 0) }, 1)
        let current = (shown + [debtPart].compactMap { $0 }).first { $0.id == selected }
        let cash = assetParts.first { $0.id == debtSourceID }
        return DonutChart(slices: assetParts.map { .init(id: $0.id, color: $0.color, value: $0.value) },
                          selected: $selected, progress: appeared ? 1 : 0,
                          inset: debt > 0 && (cash?.value ?? 0) > 0
                            ? .init(id: AssetCategory.liability.rawValue, sliceID: debtSourceID,
                                    fraction: debt / cash!.value, color: Self.debtColor)
                            : nil)
            .overlay {
                VStack(spacing: 3) {
                    if let current {
                        let isDebt = current.isLiabilityPart
                        let isNet = current.id == Self.netID
                        Text(current.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        CountingMoney(value: isDebt ? -current.value : current.value, hidden: store.hideAmounts)
                            .font(.system(size: 22, weight: .regular))
                        Text(isDebt ? "從現金與存款扣除"
                             : (isNet ? "" : "佔淨資產 ") + (max(current.value, 0) / netTotal).formatted(.percent.precision(.fractionLength(1))))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text(debt > 0 ? "淨資產" : "總資產")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        CountingMoney(value: appeared ? assets - debt : 0, hidden: store.hideAmounts)
                            .font(.system(size: 22, weight: .regular))
                        Text(debt > 0 ? "總資產 − 負債" : "\(assetParts.count) 個\(grouping == .category ? "分類" : "幣別")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 46)
                .allowsHitTesting(false)
                .animation(.snappy(duration: 0.25), value: selected)
            }
    }

    /// 資產各類以總資產為 100%；負債放在分隔線下，以負數顯示（佔總資產多少要扣掉）
    /// 比例的算法：加密貨幣、股票、現金與存款（扣掉負債）三項，合計是淨資產。負債不單獨算一項
    private func legend(_ assetParts: [Part], debtPart: Part?, assets: Double) -> some View {
        let parts = netParts(assetParts, debtPart: debtPart)
        let total = max(parts.reduce(0) { $0 + max($1.value, 0) }, 1)
        return VStack(spacing: 4) {
            ForEach(parts) { p in
                legendRow(p, share: max(p.value, 0) / total)
                if p.deducted > 0, let debtPart { debtRow(debtPart, cash: p.gross) }
            }
        }
    }

    /// 現金下面的一列：負債用紅色標出來，佔現金多少（對應圓環裡現金那塊中間的紅線）
    private func debtRow(_ d: Part, cash: Double) -> some View {
        let share = cash > 0 ? d.value / cash : 0
        let isSelected = selected == d.id
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("−").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Circle().fill(Self.debtColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("負債").font(.subheadline.weight(.medium))
                    Text("\(d.count) 個帳戶 · 從現金與存款扣除").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    MoneyText(value: -d.value).font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        if let old = d.previous {
                            // 以對淨資產的影響上色：負債變少是好事
                            DeltaText(delta: old - d.value, base: old, showPercentOnly: true)
                        }
                        Text("佔現金 " + share.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption).monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(Self.debtColor)
                        .frame(width: max(geo.size.width * min(share, 1) * (appeared ? 1 : 0), appeared ? 4 : 0))
                }
            }
            .frame(height: 3)
            .padding(.leading, 38)
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(isSelected ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(selected == nil || isSelected || selected == debtSourceID ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.2)) { selected = inside ? d.id : (selected == d.id ? nil : selected) }
        }
        .onTapGesture { tab = .accounts(AccountsFilter(.liability)) }
        .help("查看負債的帳戶")
    }

    /// 把負債從現金（幣別分組時是台幣）那一項扣掉；上一筆的數字也一樣扣，漲跌才對得上
    private func netParts(_ assetParts: [Part], debtPart: Part?) -> [Part] {
        guard let debtPart, debtPart.value > 0 else { return assetParts }
        return assetParts.map { p in
            guard p.id == debtSourceID else { return p }
            return Part(id: p.id, title: p.title, symbol: p.symbol, color: p.color,
                        value: p.value - debtPart.value,
                        previous: zip2(p.previous, debtPart.previous).map { $0 - $1 },
                        count: p.count, category: p.category, deducted: debtPart.value, gross: p.value)
        }
    }

    private func zip2(_ a: Double?, _ b: Double?) -> (Double, Double)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

    static let netID = "net-worth"

    /// 負債是現金要還掉的部分：在「現金與存款」（幣別分組時是台幣）那一塊裡面畫一條更細的灰線，
    /// 長度是負債佔現金的比例。現金本身完整呈現
    private var debtSourceID: String { grouping == .category ? AssetCategory.cash.rawValue : Currency.twd.rawValue }
    /// 負債的顏色：淺薄荷綠。跟現金同色系（紅配綠太衝），但比現金亮，
    /// 現金那塊變淡時（滑到負債）也看得清楚；深綠在深色背景和變淡的現金上都太不明顯
    static let debtColor = Color(hue: 0.42, saturation: 0.28, brightness: 0.95)


    private func legendRow(_ p: Part, share: Double, isDeduction: Bool = false) -> some View {
        let isSelected = selected == p.id
        let row = VStack(spacing: 8) {
            HStack(spacing: 12) {
                // 分類只用一個小色點對應圓環的顏色
                Circle().fill(p.color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.subheadline.weight(.medium))
                    Text(p.deducted > 0 && !store.hideAmounts
                         ? "存款 \(Fmt.money(p.gross, .twd)) − 負債 \(Fmt.money(p.deducted, .twd))"
                         : p.id == Self.netID ? "總資產 − 負債" : "\(p.count) 個帳戶")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    MoneyText(value: isDeduction ? -p.value : p.value).font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        if let old = p.previous {
                            // 負債以「對淨資產的影響」上色：負債變少是好事
                            if isDeduction {
                                DeltaText(delta: old - p.value, base: old, showPercentOnly: true)
                            } else {
                                DeltaText(delta: p.value - old, base: old, showPercentOnly: true)
                            }
                        }
                        Text((isDeduction ? "−" : "") + share.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
                if p.category != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(p.color)
                        .frame(width: max(geo.size.width * min(share, 1) * (appeared ? 1 : 0), appeared ? 4 : 0))
                }
            }
            .frame(height: 4)
            .padding(.leading, 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(isSelected ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(selected == nil || isSelected ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.2)) { selected = inside ? p.id : (selected == p.id ? nil : selected) }
        }

        return Group {
            if let category = p.category {
                Button { tab = .accounts(AccountsFilter(category)) } label: { row }
                    .buttonStyle(.plain)
                    .help("查看\(category.title)的帳戶")
            } else {
                row
            }
        }
    }
}

/// 自己畫的圓環圖：每一段是一條圓弧，進場時順時針展開；被選取的那段會變粗，其他變淡
private struct DonutChart: View {
    struct Slice: Identifiable {
        let id: String
        let color: Color
        let value: Double
    }

    private struct Arc: Identifiable {
        let id: String
        let color: Color
        let start: CGFloat
        let end: CGFloat
    }

    /// 畫在某一段裡面、更細的一條線（例如現金裡要還掉的負債）：從那一段的尾端往前，佔那一段的 fraction
    struct Inset {
        /// 這條線自己的 id（滑到圖例「負債」那一列時亮起）
        let id: String
        let sliceID: String
        let fraction: Double
        let color: Color
    }

    let slices: [Slice]
    @Binding var selected: String?
    /// 0 → 1：進場動畫的進度
    var progress: CGFloat
    var lineWidth: CGFloat = 26
    var inset: Inset? = nil

    /// 每一段的弧長（佔整圈的比例）。太小的段落放大到剛好放得下一顆圓頭，
    /// 多出來的長度從其他段按比例扣掉，所以每一段都能維持圓角。
    private func arcs(minSpan: CGFloat) -> [Arc] {
        let total = max(slices.reduce(0) { $0 + $1.value }, 1)
        var spans = slices.map { CGFloat($0.value / total) }
        let small = spans.indices.filter { spans[$0] < minSpan }
        // 全部都很小（例如只有兩三段）時不調整，避免超過一整圈
        if !small.isEmpty, CGFloat(small.count) * minSpan < 0.5 {
            let big = spans.indices.filter { !small.contains($0) }
            let bigTotal = big.reduce(0) { $0 + spans[$1] }
            let extra = small.reduce(0) { $0 + (minSpan - spans[$1]) }
            if bigTotal > extra {
                let scale = (bigTotal - extra) / bigTotal
                for i in big { spans[i] *= scale }
                for i in small { spans[i] = minSpan }
            }
        }
        var cursor: CGFloat = 0
        return zip(slices, spans).map { s, span in
            defer { cursor += span }
            return Arc(id: s.id, color: s.color, start: cursor, end: cursor + span)
        }
    }

    /// 圓頭線帽會往兩端各多畫半個線寬，段落之間的間隔要把它算進去
    private func gap(radius: CGFloat) -> CGFloat { (lineWidth + 5) / (2 * .pi * radius) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // 留空間給選取時變粗的線條和光暈
            let radius = (side - lineWidth - 18) / 2
            let gap = gap(radius: radius)
            // 比一顆圓點還短的段落放大到剛好是一顆圓點（再多一點點，才畫得出圓頭）
            let arcs = arcs(minSpan: gap + 0.0005)
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.05), lineWidth: lineWidth)
                    .frame(width: radius * 2, height: radius * 2)
                ForEach(arcs) { arc in
                    segment(arc, gap: gap, radius: radius)
                }
                if let inset, let arc = arcs.first(where: { $0.id == inset.sliceID }) {
                    insetLine(inset, in: arc, gap: gap, radius: radius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): select(hit(point, in: geo.size, radius: radius, arcs: arcs))
                case .ended: select(nil)
                }
            }
            .onTapGesture { point in
                let id = hit(point, in: geo.size, radius: radius, arcs: arcs)
                select(selected == id ? nil : id)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeOut(duration: 0.4), value: slices.map(\.value))
    }

    /// 段落中間的細線：跟著那一段一起淡出、一起進場
    @ViewBuilder private func insetLine(_ inset: Inset, in arc: Arc, gap: CGFloat, radius: CGFloat) -> some View {
        let visibleStart = arc.start + gap / 2, visibleEnd = arc.end - gap / 2
        // 滑到負債時變粗，現金那塊變淡，細線維持全亮
        let width: CGFloat = selected == inset.id ? 11 : 7
        // 細線也是圓頭：兩端各縮半個細線寬，才不會凸出段落
        let capInset = width / 2 / (2 * .pi * radius)
        let length = max((visibleEnd - visibleStart) * CGFloat(min(max(inset.fraction, 0), 1)) - 2 * capInset, 0.0005)
        let to = visibleEnd - capInset
        let from = max(to - length, visibleStart + capInset)
        Circle()
            .trim(from: from * progress, to: max(to * progress, from * progress))
            .stroke(inset.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
            .opacity(selected == nil || selected == arc.id || selected == inset.id ? 1 : 0.28)
            .allowsHitTesting(false)
    }

    @ViewBuilder private func segment(_ arc: Arc, gap: CGFloat, radius: CGFloat) -> some View {
        let isSelected = selected == arc.id
        let mid = (arc.start + arc.end) / 2
        let half = max((arc.end - arc.start - gap) / 2, 0.00025)
        let from = (mid - half) * progress
        let to = max((mid + half) * progress, from)
        Circle()
            .trim(from: from, to: to)
            .stroke(arc.color,
                    style: StrokeStyle(lineWidth: isSelected ? lineWidth + 7 : lineWidth, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
            .opacity(selected == nil || isSelected ? 1 : 0.28)
    }

    private func select(_ id: String?) {
        guard id != selected else { return }
        withAnimation(.easeOut(duration: 0.2)) { selected = id }
    }

    /// 滑鼠或手指的位置落在哪一段（不在圓環上就回傳 nil）
    private func hit(_ point: CGPoint, in size: CGSize, radius: CGFloat, arcs: [Arc]) -> String? {
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let distance = sqrt(dx * dx + dy * dy)
        guard abs(distance - radius) <= lineWidth / 2 + 10 else { return nil }
        var fraction = atan2(dx, -dy) / (2 * .pi)   // 從 12 點鐘方向順時針
        if fraction < 0 { fraction += 1 }
        return arcs.first { fraction >= $0.start && fraction < $0.end }?.id
    }
}

/// 會跟著動畫逐格跳動的金額（圓環中間的數字）
private struct CountingMoney: View, Animatable {
    var value: Double
    var hidden: Bool

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(hidden ? "••••••" : Fmt.money(value, .twd))
            .monospacedDigit()
    }
}

// MARK: - 市場

/// 匯率、幣價與持股現價：每個報價一張小卡，只放數字與漲跌
private struct MarketCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?

    private struct Item: Identifiable {
        let id: String
        let title: String
        let badge: AnyView
        let value: Double
        let prefix: String
        var digits: ClosedRange<Int>? = nil
        let old: Double?
    }

    private var items: [Item] {
        var out = Quote.allCases.map { q -> Item in
            Item(id: q.id, title: q.title, badge: AnyView(Image(systemName: q.symbol)),
                 value: snapshot.quotes[q] ?? 0, prefix: "", old: previous?.quotes[q])
        }
        // 持股的現價（即時模式為即時股價，否則為該筆紀錄的股價）
        var seen = Set<String>()
        for p in snapshot.holdings.values.flatMap({ $0 }) where seen.insert(p.symbol).inserted {
            guard let price = snapshot.stockPrices[p.symbol] else { continue }
            let cur = store.liveStocks[p.symbol]?.currency ?? Self.guessCurrency(p.symbol)
            out.append(Item(id: p.symbol, title: p.name.isEmpty ? StockService.displaySymbol(p.symbol) : p.name,
                            badge: AnyView(Text(StockService.displaySymbol(p.symbol)).monospacedDigit()),
                            value: price, prefix: cur.symbol, digits: 0...(cur == .jpy ? 1 : 2),
                            old: previous?.stockPrices[p.symbol]))
        }
        return out
    }

    private static func guessCurrency(_ symbol: String) -> Currency {
        if symbol.hasSuffix(".TW") || symbol.hasSuffix(".TWO") { return .twd }
        if symbol.hasSuffix(".T") { return .jpy }
        return .usd
    }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("市場").font(.headline.weight(.medium))
                if let d = previous?.date {
                    Text("漲跌 vs \(d.formatted(.dateTime.month(.defaultDigits).day()))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            let items = items
            // 寬螢幕四張一排，窄螢幕兩張一排
            ViewThatFits(in: .horizontal) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(items) { tile($0) }
                }
                .frame(minWidth: 760)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(items) { tile($0) }
                }
            }
        }
    }

    private func tile(_ item: Item) -> some View {
        let change = item.old.map { item.value - $0 } ?? 0
        let value = item.value

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                item.badge.foregroundStyle(.secondary)
                Text(item.title).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption)
            HStack(alignment: .firstTextBaseline) {
                Text(item.prefix + Fmt.number(value, digits: item.digits ?? 0...(value < 1 ? 5 : value < 100 ? 3 : 0)))
                    .font(.system(size: 17, weight: .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if let old = item.old, old != 0 {
                    let pct = change / old
                    // 四捨五入後是 0.0% 的就用灰色，不要紅綠
                    Text(Fmt.percent(pct))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(store.deltaColor(abs(pct) < 0.0005 ? 0 : change))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 接下來要繳

/// 負債帳戶設定了結帳日、繳費日時，列出接下來 30 天內的日子；繳費日帶出最近一筆紀錄的應繳金額
private struct UpcomingBillsCard: View {
    @Environment(\.portfolio) private var store
    let record: Snapshot

    private var events: [BillEvent] { store.billEvents(from: .now, within: 30) }

    @State private var editing: BillEvent?
    @State private var draftDate = Date.now
    /// 貸款的預約轉帳設定（點貸款那一列時）
    @State private var editingLoan: BillEvent?
    @State private var loanScheduled = false
    @State private var loanUntil = Date.now
    @State private var loanTo: UUID?

    /// 還在寬限期、還不用繳的貸款
    private var notStartedLoans: [Account] {
        store.activeAccounts(in: .liability).filter { $0.loanNotStarted() && $0.loanPaymentDay != nil }
    }

    var body: some View {
        let events = events
        if !events.isEmpty || !notStartedLoans.isEmpty {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Text("繳費與結帳").font(.headline.weight(.medium))
                    Text("30 天內").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    let pending = events.reduce(0) { $0 + (store.paymentStatus(for: $1)?.pendingCount ?? 0) }
                    if pending > 0 {
                        Label("\(pending) 筆還沒處理（預約轉帳／換匯）", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if events.contains(where: \.needsConfirm) {
                        Label("有日期從上個月帶入，請確認", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                // 繳費和結帳分兩欄並排；畫面窄時上下排
                let due = events.filter { $0.kind == .due }
                let statement = events.filter { $0.kind == .statement }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        column("繳費", systemImage: "creditcard", events: due, loans: notStartedLoans)
                        column("結帳", systemImage: "doc.text", events: statement)
                    }
                    .frame(minWidth: 640)
                    VStack(alignment: .leading, spacing: 16) {
                        column("繳費", systemImage: "creditcard", events: due, loans: notStartedLoans)
                        column("結帳", systemImage: "doc.text", events: statement)
                    }
                }
            }
        }
    }

    private func column(_ title: String, systemImage: String, events: [BillEvent], loans: [Account] = []) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if events.isEmpty {
                Text("30 天內沒有").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(6).enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider().opacity(0.6) }
                        row(e)
                    }
                }
            }
            // 寬限期中的貸款：還不用繳，標出開始繳費的日期
            ForEach(loans) { a in
                if let start = a.loanStartDate {
                    Label("\(a.name)：\(start.formatted(.dateTime.year().month(.defaultDigits).day())) 起開始繳",
                          systemImage: "hourglass")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 點一列可以確認或改日期（遇到假日不同天）
    private func row(_ e: BillEvent) -> some View {
        if e.account.isLoan {
            // 貸款每月固定日期扣款，日期不用確認；點一下設定預約轉帳到哪天、轉入哪個帳戶
            return AnyView(Button {
                let a = store.account(id: e.account.id) ?? e.account
                loanScheduled = a.paymentScheduledUntil != nil
                loanUntil = a.paymentScheduledUntil ?? e.date
                loanTo = a.paymentAccountID
                editingLoan = e
            } label: {
                rowContent(e).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("點一下設定預約轉帳")
            .popover(item: Binding(get: { editingLoan?.id == e.id ? editingLoan : nil },
                                   set: { if $0 == nil { editingLoan = nil } }), arrowEdge: .trailing) { ev in
                loanPopover(ev)
            })
        }
        return AnyView(Button {
            draftDate = e.date
            editing = e
        } label: {
            rowContent(e).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(e.needsConfirm ? "從上個月同一天帶入，點一下確認日期" : "點一下修改日期")
        .popover(item: Binding(get: { editing?.id == e.id ? editing : nil },
                               set: { if $0 == nil { editing = nil } }), arrowEdge: .trailing) { ev in
            VStack(alignment: .leading, spacing: 12) {
                Text("\(ev.name) · \(ev.title)日").font(.headline)
                if let members = ev.memberNames {
                    Text("同一間銀行一起改：\(members)").font(.caption).foregroundStyle(.secondary)
                }
                if ev.needsConfirm {
                    Text("從上個月同一天帶入，遇到假日可能不同，請確認。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DatePicker("日期", selection: $draftDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                switch store.paymentStatus(for: ev) {
                case .autoDebit?:
                    Label("自動扣款，不用另外轉帳", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                case .nothingDue?:
                    Label("本期沒有要繳的金額，不用處理", systemImage: "minus.circle").font(.caption).foregroundStyle(.secondary)
                case .tasks(let tasks)?:
                    // 每個要繳的幣別一個勾：台幣「已設定預約轉帳」、外幣「已換匯日幣」等；不用繳的幣別不列
                    ForEach(tasks) { t in
                        Toggle("這期\(t.doneTitle)", isOn: Binding(
                            get: {
                                if case .tasks(let now)? = store.paymentStatus(for: ev) {
                                    return now.first { $0.currency == t.currency }?.done ?? false
                                }
                                return false
                            },
                            set: { store.setPaymentDone($0, currency: t.currency, for: ev) }))
                    }
                case nil:
                    EmptyView()
                }
                HStack {
                    Spacer()
                    Button("取消") { editing = nil }
                    Button(ev.needsConfirm && Calendar.current.isDate(draftDate, inSameDayAs: ev.date) ? "確認是這天" : "儲存") {
                        store.setBillDate(draftDate, kind: ev.kind, for: ev.account.id)
                        editing = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 300)
        })
    }

    /// 貸款：設定預約轉帳到哪天、轉入哪個帳戶
    private func loanPopover(_ ev: BillEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(ev.account.name) · 扣款").font(.headline)
            Text("每月 \(ev.account.loanPaymentDay ?? 0) 號扣款" +
                 (ev.loanPayment.map { "，每期 " + Fmt.money($0, ev.account.currency) } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            if ev.account.autoDebit == true {
                Label("自動扣款，不用另外轉帳", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("已設定預約轉帳", isOn: $loanScheduled)
                if loanScheduled {
                    DatePicker("設定到", selection: $loanUntil, displayedComponents: .date)
                    Picker("轉入帳戶", selection: $loanTo) {
                        Text("不指定").tag(UUID?.none)
                        ForEach(store.activeAccounts(in: .cash)) { a in Text(a.name).tag(UUID?.some(a.id)) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { editingLoan = nil }
                Button("儲存") {
                    store.setLoanTransfer(until: loanScheduled ? loanUntil : nil, to: loanTo, for: ev.account.id)
                    editingLoan = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(ev.account.autoDebit == true)
            }
        }
        .padding()
        .frame(width: 320)
    }

    /// 繳費方式：自動扣款、已設定預約轉帳，或還沒設定（快到期時變紅）
    @ViewBuilder private func paymentStatusLabel(_ e: BillEvent, daysLeft: Int) -> some View {
        switch store.paymentStatus(for: e) {
        case .autoDebit?:
            Label("自動扣款", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        case .tasks(let tasks)?:
            // 每個幣別一行：完成是綠色，還沒處理是橘色（剩 3 天內變紅）
            VStack(alignment: .leading, spacing: 1) {
                ForEach(tasks) { t in
                    if t.done {
                        Label(t.doneTitle + loanDetail(t), systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Label(t.pendingTitle, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(daysLeft <= 3 ? Color.red : Color.orange)
                    }
                }
            }
        case .nothingDue?:
            Label("本期無需繳費", systemImage: "minus.circle").font(.caption).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    /// 貸款的預約轉帳：設定到哪天、轉入哪個帳戶，例如「（到 2027/3/22・轉入 LINE Bank）」
    private func loanDetail(_ t: PaymentTask) -> String {
        var parts: [String] = []
        if let until = t.scheduledUntil { parts.append("到 " + until.formatted(.dateTime.year().month(.defaultDigits).day())) }
        if let to = t.transferTo { parts.append("轉入 " + to) }
        return parts.isEmpty ? "" : "（" + parts.joined(separator: "・") + "）"
    }

    private func amountLine(_ a: Account, _ v: Double) -> some View {
        HStack(spacing: 4) {
            if v < 0 { RefundTag() }
            if store.hideAmounts {
                Text("••••").font(.subheadline)
            } else {
                Text(Fmt.money(abs(v), a.currency)).font(.subheadline).monospacedDigit()
                if a.currency != .twd {
                    Text("（" + Fmt.money(abs(v) * store.rate(a.currency, in: record), .twd) + "）")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
    }

    private func rowContent(_ e: BillEvent) -> some View {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: e.date).day ?? 0
        let urgent = e.kind == .due && days <= 3
        // 應繳金額：各張卡換成台幣加總；外幣另外列出原幣金額
        // 貸款用每月繳款金額（帳戶金額是剩餘本金）
        let owed = e.account.isLoan
            ? (e.loanPayment.map { [(e.account, $0)] } ?? [])
            : e.accounts.compactMap { a in record.amounts[a.id].map { (a, $0) } }.filter { $0.1 != 0 }
        return HStack(spacing: 12) {
            AccountAvatar(account: e.account, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.name).lineLimit(1)
                // 欄位已經寫了繳費／結帳，這裡標星期（方便看是不是遇到假日）；同銀行多張卡時列出卡名
                Text([e.date.formatted(.dateTime.weekday(.wide)), e.memberNames].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                paymentStatusLabel(e, daysLeft: days)
            }
            Spacer(minLength: 8)
            if e.kind == .due, !owed.isEmpty {
                // 每張卡各一行、分開繳，不合計：外幣寫原幣並附台幣換算，負數是退款
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(owed, id: \.0.id) { a, v in
                        amountLine(a, v)
                    }
                }
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(e.date.formatted(.dateTime.month(.defaultDigits).day()))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                if e.needsConfirm {
                    Text("請確認").font(.caption.weight(.medium)).foregroundStyle(.orange)
                } else {
                    Text(days == 0 ? "今天" : days == 1 ? "明天" : "剩 \(days) 天")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(urgent ? Color.red : Color.secondary)
                }
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}
