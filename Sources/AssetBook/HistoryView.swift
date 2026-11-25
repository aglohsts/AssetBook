import SwiftUI

struct HistoryView: View {
    @Environment(\.portfolio) private var store
    @State private var pendingDelete: Snapshot?
    @State private var mode: Mode = .calendar
    /// 目前顯示的月份（該月 1 號）
    @State private var month: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    enum Mode: String, CaseIterable, Identifiable {
        case calendar = "日曆", list = "列表"
        var id: Self { self }
    }

    var body: some View {
        Group {
            switch mode {
            case .calendar: calendarView
            case .list: listView
            }
        }
        .navigationTitle("歷史紀錄")
        .navigationDestination(for: Snapshot.self) { SnapshotDetailView(snapshot: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("檢視", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Menu {
                    Button("複製為試算表", systemImage: "doc.on.clipboard") { store.copySheetToClipboard() }
                    Button("匯出 CSV 檔…", systemImage: "square.and.arrow.down") { store.isExportingSheet = true }
                } label: {
                    Label("匯出成試算表", systemImage: "tablecells")
                }
                .help("匯出所有紀錄，可貼到 Google 試算表")
                UpdateToolbarButton(store: store)
            }
        }
        .onAppear {
            // 第一次打開時，跳到最新紀錄所在的月份
            if let last = store.snapshots.last?.date,
               let start = Calendar.current.dateInterval(of: .month, for: last)?.start { month = start }
        }
        .confirmationDialog("刪除這筆紀錄？", isPresented: .init(get: { pendingDelete != nil },
                                                          set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { s in
            Button("刪除 \(s.date.formatted(.dateTime.month(.defaultDigits).day())) 的紀錄", role: .destructive) {
                withAnimation { store.delete(s) }
            }
        } message: { _ in
            Text("這個動作無法復原。")
        }
    }

    // MARK: 日曆

    private var calendarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    monthHeader
                    weekdayRow
                    dayGrid
                }
                monthSummary
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
    }

    private var cal: Calendar { .current }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.easeOut(duration: 0.2)) { month = d }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Text(month.formatted(.dateTime.year().month(.wide)))
                .font(.title3.weight(.medium))
            Spacer()
            Button("今天") {
                if let start = cal.dateInterval(of: .month, for: .now)?.start {
                    withAnimation(.easeOut(duration: 0.2)) { month = start }
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .help("上個月")
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .help("下個月")
        }
        .foregroundStyle(.primary)
    }

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 這個月的每一格：前面補空白，讓 1 號對到正確的星期
    private var dayCells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in 0..<count { cells.append(cal.date(byAdding: .day, value: d, to: interval.start)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var dayGrid: some View {
        // 同一天有手動記錄就用手動的，否則用自動估值點
        let byDay = Dictionary((store.autoSnapshots + store.snapshots).map { (cal.startOfDay(for: $0.date), $0) },
                               uniquingKeysWith: { _, manual in manual })
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    if let snap = byDay[cal.startOfDay(for: day)] {
                        let auto = store.isAuto(snap)
                        NavigationLink(value: snap) {
                            DayCell(day: day, snapshot: snap, previous: store.snapshot(before: snap), isAuto: auto)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if auto {
                                Button("刪除估算", systemImage: "trash", role: .destructive) { store.deleteAuto(snap) }
                            } else {
                                Button("刪除紀錄", systemImage: "trash", role: .destructive) { pendingDelete = snap }
                            }
                        }
                    } else {
                        DayCell(day: day, snapshot: nil, previous: nil)
                    }
                } else {
                    Color.clear.frame(height: 76)
                }
            }
        }
    }

    /// 這個月的紀錄數與淨資產變化（和上個月最後一筆比）
    @ViewBuilder private var monthSummary: some View {
        let inMonth = store.snapshots.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        if let last = inMonth.last {
            let baseline = store.snapshots.last { $0.date < (inMonth.first?.date ?? last.date) } ?? inMonth.first!
            let delta = store.netWorth(last) - store.netWorth(baseline)
            let autoCount = store.autoSnapshots.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }.count
            HStack(spacing: 8) {
                Text("本月 \(inMonth.count) 筆紀錄" + (autoCount > 0 ? "、\(autoCount) 天估算（≈）" : ""))
                if baseline.id != last.id {
                    Text("·")
                    DeltaText(delta: delta)
                    Text("vs \(baseline.date.formatted(.dateTime.month(.defaultDigits).day()))")
                }
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        } else {
            Text("這個月沒有紀錄")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: 列表

    private var listView: some View {
        List {
            ForEach(store.snapshots.reversed()) { s in
                NavigationLink(value: s) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.date.formatted(.dateTime.year().month().day()))
                                .font(.body.weight(.medium))
                            Text(s.date.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            let net = store.netWorth(s)
                            MoneyText(value: net).font(.body.weight(.medium))
                            if let prev = store.snapshot(before: s) {
                                let old = store.netWorth(prev)
                                DeltaText(delta: net - old, base: old).font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions {
                    Button("刪除", systemImage: "trash", role: .destructive) { pendingDelete = s }
                }
                .contextMenu {
                    Button("刪除紀錄", systemImage: "trash", role: .destructive) { pendingDelete = s }
                }
            }
        }
    }
}

/// 日曆裡的一天：有紀錄就顯示淨資產與變動，點下去看那天的明細
private struct DayCell: View {
    @Environment(\.portfolio) private var store
    let day: Date
    let snapshot: Snapshot?
    let previous: Snapshot?
    /// 估算（自動估值點）：數字前加 ≈、虛線框
    var isAuto = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.caption.weight(isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : (snapshot == nil ? Color.secondary : Color.primary))
                .frame(minWidth: 20, minHeight: 20)
                .background(isToday ? Color.accentColor : .clear, in: Circle())
            if let snapshot {
                let net = store.netWorth(snapshot)
                Spacer(minLength: 0)
                // 沒記錄、App 自己估的那天前面加 ≈
                Text((isAuto ? "≈ " : "") + (store.hideAmounts ? "••" : Fmt.wan(net)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(isAuto ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let previous {
                    let d = net - store.netWorth(previous)
                    Text(store.hideAmounts ? (d > 0 ? "▲" : d < 0 ? "▼" : "—")
                                           : (d > 0 ? "+" : "") + Fmt.wan(d))
                        .font(.system(size: 10)).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(store.deltaColor(d))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(snapshot == nil || isAuto ? Color.clear : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            // 估算的那天用虛線框，跟有記錄的實心格子分開
            if isAuto {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SnapshotDetailView: View {
    @Environment(\.portfolio) private var store
    /// 點進來時的那筆紀錄；畫面上顯示的是這一天在 store 裡最新的版本（修改後會馬上更新）
    let snapshot: Snapshot
    @State private var notTodayAlert = false
    /// 點了今天紀錄中的某個帳戶：只改這一項
    @State private var editingAccount: Account?

    /// 同一天的最新紀錄：手動記錄優先，其次自動估值點，都找不到才用點進來時的資料
    private var current: Snapshot {
        let cal = Calendar.current
        return store.snapshots.last { cal.isDate($0.date, inSameDayAs: snapshot.date) }
            ?? store.autoSnapshots.last { cal.isDate($0.date, inSameDayAs: snapshot.date) }
            ?? snapshot
    }

    /// 判斷「今天」用的時間：打開畫面、按下修改、跨過午夜時都會更新
    @State private var now = Date.now
    @State private var dayEndedAlert = false

    /// 只能修改今天的紀錄；過了那天就變成唯讀
    private var isToday: Bool { Calendar.current.isDate(snapshot.date, inSameDayAs: now) }

    var body: some View {
        let snapshot = current
        let prev = store.snapshot(before: snapshot)
        List {
            Section {
                if store.isAuto(snapshot) { estimateNotice(snapshot) }
                editNotice
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("淨資產").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if store.isAuto(snapshot) { Text("≈").foregroundStyle(.secondary) }
                        MoneyText(value: store.netWorth(snapshot))
                    }
                    .font(.system(size: 34, weight: .regular))
                    if let prev {
                        let old = store.netWorth(prev)
                        DeltaBadge(delta: store.netWorth(snapshot) - old, base: old)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("報價") {
                ForEach(Quote.allCases.filter { (snapshot.quotes[$0] ?? 0) != 0 }) { q in
                    QuoteRow(quote: q, value: snapshot.quotes[q] ?? 0, previous: prev?.quotes[q])
                }
            }

            ForEach(store.activeCategories) { cat in
                Section {
                    ForEach(store.accounts(in: cat).filter { snapshot.amounts[$0.id] != nil || prev?.amounts[$0.id] != nil }) { a in
                        if isToday {
                            Button { edit(a) } label: {
                                AccountRow(account: a, snapshot: snapshot, previous: prev)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(a.isPortfolio ? "修改持股（打開更新資產）" : "修改這一項")
                        } else {
                            AccountRow(account: a, snapshot: snapshot, previous: prev)
                        }
                    }
                } header: {
                    HStack {
                        Text(cat.title)
                        Spacer()
                        MoneyText(value: store.total(cat, in: snapshot))
                    }
                }
            }
        }
        .navigationTitle(snapshot.date.formatted(.dateTime.year().month().day()))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openUpdateSheet()
                } label: {
                    if isToday {
                        Label("修改", systemImage: "square.and.pencil")
                    } else {
                        Label("已鎖定", systemImage: "lock")
                    }
                }
                .disabled(!isToday)
                .help(isToday ? "修改今天的紀錄（⌘U）" : "過去的紀錄，只能查看")
            }
        }
        .sheet(item: $editingAccount) { a in
            AmountEditor(account: a, target: current).environment(\.portfolio, store)
        }
        .onAppear { now = .now }
        // 畫面開著跨過午夜：這一頁馬上變成唯讀，正在修改的視窗也關掉，避免存到已經過去的那一天
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            let wasToday = isToday
            now = .now
            guard wasToday, !isToday else { return }
            let editing = editingAccount != nil || (store.isUpdating && store.isUpdatingTodayOnly)
            editingAccount = nil
            if store.isUpdatingTodayOnly { store.isUpdating = false }
            if editing { dayEndedAlert = true }
        }
        .alert("這一天已經結束", isPresented: $dayEndedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("已過午夜，這筆變成過去的紀錄，修改沒有儲存。要記錄今天的數字，請從總覽按「更新資產」。")
        }
        .alert("只能修改今天的紀錄", isPresented: $notTodayAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("這筆是 \(snapshot.date.formatted(.dateTime.month().day())) 的紀錄，過去的紀錄不能修改。")
        }
    }

    /// 這天沒有記錄、是 App 估的：說明餘額沿用哪一天
    private func estimateNotice(_ s: Snapshot) -> some View {
        let base = store.snapshots.last { $0.date < s.date }
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("≈ 估算 · 這天沒有記錄")
                Text(base.map { "餘額沿用 \($0.date.formatted(.dateTime.month(.defaultDigits).day()))，股價和匯率用當天的。" }
                     ?? "股價和匯率用當天的。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Text("≈").font(.title3).foregroundStyle(.secondary)
        }
    }

    /// 頁面最上方的提示：今天可以修改；過去的紀錄只能查看
    @ViewBuilder private var editNotice: some View {
        if isToday {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天的紀錄")
                    Text("點任一項目可以直接修改，過了今天就會鎖定。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "square.and.pencil").foregroundStyle(Color.accentColor)
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("過去的紀錄")
                    Text("只能查看，不能修改。只有當天的紀錄可以修改。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }

    private func openUpdateSheet() {
        now = .now
        guard isToday else { notTodayAlert = true; return }
        store.isUpdatingTodayOnly = true
        store.isUpdating = true
    }

    /// 點單一項目：一般帳戶只改這一項的金額；持股帳戶要改股數，改用完整的更新畫面
    private func edit(_ account: Account) {
        now = .now
        guard isToday else { notTodayAlert = true; return }
        if account.isPortfolio { openUpdateSheet() } else { editingAccount = account }
    }
}

/// 歷史明細裡的一列報價：灰色圖示、名稱下方標單位，數字依報價取合適的小數位數，
/// 漲跌欄固定寬度（沒有上一筆就顯示「—」），整欄數字才會對齊
private struct QuoteRow: View {
    @Environment(\.portfolio) private var store
    let quote: Quote
    let value: Double
    let previous: Double?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: quote.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.title)
                Text(quote.unit).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(quote.displayPrefix + Fmt.number(value, digits: quote.displayDigits...quote.displayDigits))
                .monospacedDigit()
            change
                .font(.caption.monospacedDigit())
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var change: some View {
        if let previous, previous != 0 {
            let pct = (value - previous) / previous
            // 四捨五入後是 0.0% 的用灰色，不要紅綠
            Text(Fmt.percent(pct))
                .foregroundStyle(store.deltaColor(abs(pct) < 0.0005 ? 0 : value - previous))
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}
