import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - 帳戶列表

/// 「全部」：資產 − 負債 = 淨資產，加上每個分類一列摘要，點下去切到該分類。
/// 單一分類：分類小計＋該分類的帳戶（股票帳戶直接展開持股）。
struct AccountsView: View {
    @Environment(\.portfolio) private var store
    @Binding var filter: AccountsFilter
    /// iPhone／iPad 顯示頂端的分段選單；Mac 改用側邊欄切換
    var showsPicker = true

    @State private var adding: AssetCategory?
    @State private var editing: Account?
    @State private var showArchived = false

    var body: some View {
        Group {
            if filter.category == nil, let latest = store.latest {
                // 跟總覽的即時模式一樣：最新紀錄 × 現在的報價，和最新紀錄比較；沒有報價時用紀錄本身
                if let live = store.liveSnapshot {
                    overviewScroll(latest: live, prev: latest)
                } else {
                    overviewScroll(latest: latest, prev: store.snapshot(before: latest))
                }
            } else {
                categoryList
            }
        }
        .navigationTitle(showsPicker ? "帳戶" : filter.title)
        .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let cat = filter.category {
                    Button { adding = cat } label: { Label(cat.addTitle, systemImage: "plus") }
                        .help(cat.addTitle)
                } else {
                    Menu {
                        ForEach(AssetCategory.allCases) { cat in
                            Button(cat.title, systemImage: cat.symbol) { adding = cat }
                        }
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                    .help("新增帳戶或信用卡")
                }
                UpdateToolbarButton(store: store)
            }
        }
        .sheet(item: $adding) { cat in
            AccountEditor(category: cat).environment(\.portfolio, store)
        }
        .sheet(item: $editing) { account in
            AccountEditor(account: account).environment(\.portfolio, store)
        }
    }

    private var categoryList: some View {
        List {
            if showsPicker {
                Section {
                    Picker("分類", selection: $filter.animation(.snappy)) {
                        ForEach(AccountsFilter.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if let latest = store.latest, let cat = filter.category {
                // 和「全部」一樣跟著即時報價：股票、加密貨幣看股價，外幣現金與負債看匯率
                if let live = store.liveSnapshot {
                    categoryPage(cat, latest: live, prev: latest)
                } else {
                    categoryPage(cat, latest: latest, prev: store.snapshot(before: latest))
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: 全部

    private func overviewScroll(latest: Snapshot, prev: Snapshot?) -> some View {
        let cats = AssetCategory.allCases.filter { !store.activeAccounts(in: $0).isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsPicker {
                    Picker("分類", selection: $filter.animation(.snappy)) {
                        ForEach(AccountsFilter.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Card { BalanceSummary(snapshot: latest, previous: prev) }

                Card {
                    CategoryTableHeader(previous: prev)
                    VStack(spacing: 0) {
                        ForEach(Array(cats.enumerated()), id: \.element.id) { i, cat in
                            if i > 0 { Divider().opacity(0.6) }
                            Button {
                                withAnimation(.snappy) { filter = AccountsFilter(cat) }
                            } label: {
                                CategorySummaryRow(category: cat, snapshot: latest, previous: prev)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("點分類查看帳戶明細，⌘1–⌘5 快速切換")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if !store.archivedAccounts.isEmpty {
                    Card {
                        DisclosureGroup(isExpanded: $showArchived) {
                            VStack(spacing: 0) {
                                ForEach(store.archivedAccounts) { account in
                                    NavigationLink(value: account) {
                                        AccountRow(account: account, snapshot: latest, previous: nil)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { actions(for: account) }
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Label("已封存（\(store.archivedAccounts.count)）", systemImage: "archivebox")
                                .foregroundStyle(.secondary)
                        }
                        Text("封存的帳戶不會出現在更新畫面，過去的紀錄會保留，淨資產歷史不受影響。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
    }

    // MARK: 單一分類

    @ViewBuilder private func categoryPage(_ cat: AssetCategory, latest: Snapshot, prev: Snapshot?) -> some View {
        let items = store.activeAccounts(in: cat)

        Section {
            CategoryOverview(category: cat, snapshot: latest, previous: prev)
        }

        if cat.isLiability, !items.isEmpty {
            // 負債分成卡費、未出帳、貸款；同一組裡依銀行排在一起
            Section {
                ForEach(LiabilityGroup.allCases.filter { g in items.contains { $0.liabilityGroup == g } }) { g in
                    let group = items.filter { $0.liabilityGroup == g }
                        .sorted { ($0.bankName ?? $0.name, $0.name) < ($1.bankName ?? $1.name, $1.name) }
                    LiabilityGroupRow(group: g, accounts: group, snapshot: latest, previous: prev)
                    accountRows(group, latest: latest, prev: prev, indent: 48)
                }
                Button {
                    adding = cat
                } label: {
                    Label(cat.addTitle, systemImage: "plus.circle.fill")
                        .foregroundStyle(cat.tint)
                }
                .buttonStyle(.borderless)
            } header: {
                if let prev {
                    Text("右側漲跌為與 \(prev.date.formatted(.dateTime.month(.defaultDigits).day())) 相比")
                        .textCase(nil)
                }
            } footer: {
                Text("這期沒有帳單的卡，在「更新資產」時按「無帳單」即可，不必刪除。種類可在帳戶編輯裡改。")
            }
        } else if cat == .cash, !items.isEmpty {
            // 現金與存款分成子分類（銀行、交易所與穩定幣、現鈔與儲值）：
            // 子分類是一列，底下縮排列出它的帳戶，和股票頁的持股一樣
            Section {
                ForEach(CashGroup.allCases.filter { g in items.contains { $0.resolvedCashGroup == g } }) { g in
                    let group = items.filter { $0.resolvedCashGroup == g }
                    CashGroupRow(group: g, accounts: group, snapshot: latest, previous: prev)
                    accountRows(group, latest: latest, prev: prev, indent: 48)
                }
                Button {
                    adding = cat
                } label: {
                    Label(cat.addTitle, systemImage: "plus.circle.fill")
                        .foregroundStyle(cat.tint)
                }
                .buttonStyle(.borderless)
            } header: {
                if let prev {
                    Text("右側漲跌為與 \(prev.date.formatted(.dateTime.month(.defaultDigits).day())) 相比")
                        .textCase(nil)
                }
            }
        } else {
            Section {
                if items.isEmpty {
                    Text(cat.isLiability ? "還沒有信用卡。" : "這個分類還沒有帳戶。")
                        .foregroundStyle(.secondary)
                }
                accountRows(items, latest: latest, prev: prev)
                if cat == .stocks {
                    ConvertToPortfolioPrompt(accounts: items.filter { !$0.isPortfolio })
                }
                Button {
                    adding = cat
                } label: {
                    Label(cat.addTitle, systemImage: "plus.circle.fill")
                        .foregroundStyle(cat.tint)
                }
                .buttonStyle(.borderless)
            } header: {
                if let prev {
                    Text("右側漲跌為與 \(prev.date.formatted(.dateTime.month(.defaultDigits).day())) 相比")
                        .textCase(nil)
                }
            } footer: {
                if cat.isLiability {
                    Text("這期沒有帳單的卡，在「更新資產」時按「無帳單」即可，不必刪除。")
                } else if cat == .stocks, items.contains(where: \.isPortfolio) {
                    Text("持股顯示的是紀錄時的股價；即時股價請看總覽或帳戶明細。")
                }
            }
        }
    }

    @ViewBuilder private func accountRows(_ list: [Account], latest: Snapshot, prev: Snapshot?,
                                          indent: CGFloat = 0) -> some View {
        ForEach(list) { account in
            NavigationLink(value: account) {
                AccountRow(account: account, snapshot: latest, previous: prev, nested: indent > 0)
                    .padding(.leading, indent)
            }
            .contextMenu { actions(for: account) }
            .swipeActions(edge: .trailing) {
                Button("封存", systemImage: "archivebox") { store.setArchived(account, true) }
                    .tint(.gray)
                Button("編輯", systemImage: "pencil") { editing = account }
                    .tint(.accentColor)
            }
            // 股票帳戶直接展開持股
            if account.isPortfolio {
                ForEach(latest.holdings[account.id] ?? []) { p in
                    PositionLine(position: p, account: account, snapshot: latest)
                }
            }
        }
    }

    @ViewBuilder private func actions(for account: Account) -> some View {
        Button("編輯…", systemImage: "pencil") { editing = account }
        if account.isArchived {
            Button("取消封存", systemImage: "tray.and.arrow.up") { store.setArchived(account, false) }
        } else {
            Button("封存", systemImage: "archivebox") { store.setArchived(account, true) }
        }
    }
}

// MARK: - 「全部」裡的分類摘要列

/// 分類表的欄位標題：金額、佔比、和上一筆紀錄比的漲跌
private struct CategoryTableHeader: View {
    let previous: Snapshot?

    private var versus: String {
        previous.map { "vs \($0.date.formatted(.dateTime.month(.defaultDigits).day()))" } ?? ""
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                Text("分類")
                Spacer(minLength: 0)
                Text("金額").frame(width: 140, alignment: .trailing)
                Text("佔比").frame(width: 64, alignment: .trailing)
                Text(versus).frame(width: 110, alignment: .trailing)
                Color.clear.frame(width: 24, height: 1)
            }
            .frame(minWidth: 620)
            HStack {
                Text("分類")
                Spacer()
                Text(previous == nil ? "金額" : "金額 · 佔比 · \(versus)")
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

private struct CategorySummaryRow: View {
    @Environment(\.portfolio) private var store
    let category: AssetCategory
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let accounts = store.activeAccounts(in: category)
        let total = store.total(category, in: snapshot)
        let gross = store.grossAssets(snapshot)
        // 金額最大的 3 個帳戶
        let top = accounts.sorted { abs(store.value(of: $0, in: snapshot)) > abs(store.value(of: $1, in: snapshot)) }.prefix(3)

        let title = HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(category.title).font(.body.weight(.medium))
                HStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, a in
                        AccountAvatar(account: a, size: 18)
                            .padding(1.5)
                            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.leading, i == 0 ? 0 : -6)
                            .zIndex(Double(3 - i))
                    }
                    Text("\(accounts.count) 個\(category.isLiability ? "卡片" : "帳戶")")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .fixedSize()
                }
            }
        }

        let share = Group {
            if !category.isLiability, gross > 0 {
                Text((total / gross).formatted(.percent.precision(.fractionLength(0))))
            } else {
                Text("—")
            }
        }
        .foregroundStyle(.secondary)

        let change = Group {
            if let previous {
                let old = store.total(category, in: previous)
                if category.isLiability {
                    LiabilityChange(now: -total, before: -old)
                } else {
                    DeltaText(delta: total - old, base: old, showPercentOnly: true)
                }
            }
        }

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                title
                Spacer(minLength: 8)
                CategoryTotalText(category: category, total: total).font(.system(size: 17)).frame(width: 140, alignment: .trailing)
                share.font(.callout).monospacedDigit().frame(width: 64, alignment: .trailing)
                change.font(.callout).monospacedDigit().frame(width: 110, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)
            }
            .frame(minWidth: 620)
            HStack(spacing: 8) {
                title
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    CategoryTotalText(category: category, total: total).font(.system(size: 17))
                    HStack(spacing: 8) {
                        if !category.isLiability, gross > 0 { share }
                        change
                    }
                    .font(.caption).monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - 分類頁頂部

private struct CategoryOverview: View {
    @Environment(\.portfolio) private var store
    let category: AssetCategory
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let total = store.total(category, in: snapshot)
        let gross = store.grossAssets(snapshot)
        let count = store.activeAccounts(in: category).count
            // 負債的合計包含卡費、未出帳與貸款餘額，是總額而不是本期要繳的錢
        VStack(alignment: .leading, spacing: 8) {
            Label(category.isLiability ? "負債總額" : category.title, systemImage: category.symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(category.tint)
            let isLive = snapshot.id == PortfolioStore.liveSnapshotID
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isLive ? "chart.line.uptrend.xyaxis" : "pencil")
                    .font(.system(size: 18, weight: .regular)).foregroundStyle(.secondary)
                    .help(isLive ? "即時估算 \(snapshot.date.formatted(date: .omitted, time: .shortened))：餘額沿用最近一次記錄，股價和匯率用最新的" : "手動記錄")
                CategoryTotalText(category: category, total: total)
            }
            .font(.system(size: 32, weight: .regular))
            HStack(spacing: 10) {
                if let previous {
                    let old = store.total(category, in: previous)
                    if category.isLiability {
                        LiabilityChange(now: -total, before: -old)
                        Text("較 \(previous.date.formatted(.dateTime.month(.defaultDigits).day()))").foregroundStyle(.secondary)
                    } else {
                        DeltaBadge(delta: total - old, base: old)
                        Text("較 \(previous.date.formatted(.dateTime.month(.defaultDigits).day()))").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !category.isLiability, gross > 0 {
                    Text("佔總資產 \((total / gross).formatted(.percent.precision(.fractionLength(0)))) · \(count) 個帳戶")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(count) 張卡").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
    }
}

/// 現金分頁裡的子分類列：和股票頁的「台股」「美股」一樣，底下縮排列出帳戶
private struct CashGroupRow: View {
    @Environment(\.portfolio) private var store
    let group: CashGroup
    let accounts: [Account]
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let total = accounts.reduce(0) { $0 + store.value(of: $1, in: snapshot) }
        let old = previous.map { p in accounts.reduce(0) { $0 + store.value(of: $1, in: p) } }
        let cash = store.total(.cash, in: snapshot)
        HStack(spacing: 12) {
            Image(systemName: group.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).font(.body.weight(.medium))
                Text("\(accounts.count) 個帳戶" + (cash > 0 ? " · 佔 \((total / cash).formatted(.percent.precision(.fractionLength(0))))" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(value: total).font(.title3.weight(.semibold))
                if let old {
                    DeltaText(delta: total - old, base: old, showPercentOnly: true).font(.caption)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// 負債分頁裡的子分類列（卡費、未出帳、貸款）：顯示合計，底下縮排列出帳戶
private struct LiabilityGroupRow: View {
    @Environment(\.portfolio) private var store
    let group: LiabilityGroup
    let accounts: [Account]
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        // value(of:) 對負債是負的；這裡顯示成要繳／要還的正數
        let owed = -accounts.reduce(0) { $0 + store.value(of: $1, in: snapshot) }
        let old = previous.map { p in -accounts.reduce(0) { $0 + store.value(of: $1, in: p) } }
        HStack(spacing: 12) {
            Image(systemName: group.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).font(.body.weight(.medium))
                Text("\(accounts.count) 個帳戶 · \(group.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                OwedAmount(owed: owed).font(.title3.weight(.semibold))
                if let old { LiabilityChange(now: owed, before: old).font(.caption) }
            }
        }
        .padding(.vertical, 3)
    }
}

/// 分類合計：負債顯示要繳的正數，退款用「退款」標籤（跟帳戶列一致）
private struct CategoryTotalText: View {
    let category: AssetCategory
    let total: Double

    var body: some View {
        if category.isLiability {
            OwedAmount(owed: -total)
        } else {
            MoneyText(value: total)
        }
    }
}

/// 負債的變化用中性色，帳單變多不是「漲」
private struct LiabilityChange: View {
    @Environment(\.portfolio) private var store
    let now: Double
    let before: Double

    var body: some View {
        let d = now - before
        Group {
            if abs(d) < 1 {
                Text("持平")
            } else if store.hideAmounts {
                Text(d > 0 ? "▲" : "▼")
            } else {
                Text("\(d > 0 ? "▲" : "▼") \(Fmt.money(abs(d), .twd))")
            }
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

/// 股票分頁裡，帳戶下方展開的一檔持股
private struct PositionLine: View {
    @Environment(\.portfolio) private var store
    let position: Position
    let account: Account
    let snapshot: Snapshot

    var body: some View {
        let price = snapshot.stockPrices[position.symbol] ?? 0
        HStack(spacing: 10) {
            TickerBadge(symbol: position.symbol, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(position.name).font(.subheadline).lineLimit(1)
                Text("\(Fmt.number(position.shares, digits: 0...4)) 股 × \(Fmt.number(price, digits: 0...2))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            MoneyText(value: position.shares * price, currency: account.currency)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 48)
    }
}

// MARK: - 總覽：資產 − 負債 = 淨資產

private struct BalanceSummary: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let gross = store.grossAssets(snapshot)
        let debt = -store.total(.liability, in: snapshot)
        let net = store.netWorth(snapshot)
        let parts = AssetCategory.allCases.filter { !$0.isLiability }
            .map { ($0, max(store.total($0, in: snapshot), 0)) }
            .filter { $0.1 > 0 }
        // 跟總覽的圓環一樣：負債是現金要還掉的部分，畫在現金那段裡面；佔比以淨資產計（現金扣掉負債）
        let cash = parts.first { $0.0 == .cash }?.1 ?? 0
        let debtInCash = debt > 0 && cash > 0
        let shareBase = debtInCash ? max(net, 1) : gross

        VStack(alignment: .leading, spacing: 20) {
            // 淨資產是主角；資產與負債是它的組成
            VStack(alignment: .leading, spacing: 6) {
                let isLive = snapshot.id == PortfolioStore.liveSnapshotID
                Text(isLive
                     ? "淨資產 · 即時估算 \(snapshot.date.formatted(date: .omitted, time: .shortened))"
                     : "淨資產 · \(snapshot.date.formatted(.dateTime.month(.defaultDigits).day())) 紀錄")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: isLive ? "chart.line.uptrend.xyaxis" : "pencil")
                        .font(.system(size: 20, weight: .regular)).foregroundStyle(.secondary)
                    MoneyText(value: net)
                        .foregroundStyle(isLive ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .font(.system(size: 36, weight: .regular))
                if let previous {
                    let old = store.netWorth(previous)
                    HStack(spacing: 8) {
                        DeltaBadge(delta: net - old, base: old)
                        Text("vs \(previous.date.formatted(.dateTime.month(.defaultDigits).day()))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                part("資產", gross)
                part("負債", debt, minus: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                // 資產分類比例
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        // 現金那段的右邊漸漸淡成負債（跟總覽圓環同一個淺薄荷綠），沒有硬邊；左邊都是正的、右邊是要還掉的
                        ForEach(parts, id: \.0) { cat, v in
                            let owed = cat == .cash && debtInCash ? min(debt, v) : 0
                            Rectangle().fill(owed > 0 ? AnyShapeStyle(debtGradient(cat.tint, owedShare: owed / v))
                                                      : AnyShapeStyle(cat.tint))
                                .frame(width: max(geo.size.width * v / gross - 2, 2))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)

                HStack(spacing: 16) {
                    ForEach(parts, id: \.0) { cat, v in
                        let value = cat == .cash && debtInCash ? v - debt : v
                        HStack(spacing: 6) {
                            Circle().fill(cat.tint).frame(width: 6, height: 6)
                            Text(cat.title).foregroundStyle(.secondary)
                            Text((value / shareBase).formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                    }
                    if debtInCash {
                        HStack(spacing: 6) {
                            Circle().fill(Color.debt).frame(width: 6, height: 6)
                            Text("負債").foregroundStyle(.secondary)
                            Text("佔現金 " + (debt / cash).formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        }
    }

    /// 現金 → 負債的漸層：交界前後各留一小段過渡，比例本身不變
    private func debtGradient(_ cash: Color, owedShare: Double) -> LinearGradient {
        let edge = 1 - min(max(owedShare, 0), 1)
        let blend = 0.08
        return LinearGradient(stops: [
            .init(color: cash, location: 0),
            .init(color: cash, location: max(edge - blend, 0)),
            .init(color: .debt, location: min(edge + blend, 1)),
            .init(color: .debt, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }

    private func part(_ title: String, _ value: Double, minus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if minus { Text("−").foregroundStyle(.tertiary) }
                MoneyText(value: value)
            }
            .font(.system(size: 20, weight: .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 帳戶列

struct AccountRow: View {
    @Environment(\.portfolio) private var store
    let account: Account
    let snapshot: Snapshot
    let previous: Snapshot?
    /// 縮排在子分類底下時，字和圖示都小一點、金額用次要色，讓子分類的小計更突出
    var nested = false

    var body: some View {
        let hasAmount = snapshot.amounts[account.id].map { $0 != 0 } ?? false
        let value = store.value(of: account, in: snapshot)

        HStack(spacing: 12) {
            AccountAvatar(account: account, size: nested ? 30 : 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(nested ? .subheadline : .body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if account.category.isLiability && !hasAmount {
                    Text("本期無帳單").foregroundStyle(.secondary)
                } else {
                    // 負債顯示為正的應繳金額；退款（溢繳）用「退款」標籤，跟其他地方一致
                    if account.category.isLiability {
                        OwedAmount(owed: -value)
                            .font(nested ? .subheadline : .body.weight(.medium))
                            .foregroundStyle(nested ? .secondary : .primary)
                    } else if nested {
                        MoneyText(value: value).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        MoneyText(value: value).fontWeight(.medium)
                    }
                }
                change.font(.caption)
            }
        }
        .padding(.vertical, 3)
    }

    /// 外幣與持有數量才顯示原幣金額；台幣帳戶只顯示備註
    private var subtitle: String? {
        if store.hideAmounts { return account.note.isEmpty ? nil : account.note }
        let amount = snapshot.amounts[account.id] ?? 0
        let native = store.nativeValue(of: account, in: snapshot) ?? 0
        var parts: [String] = []
        switch account.valuation {
        case .holding:
            parts.append("\(Fmt.number(amount, digits: 0...4)) \(account.inputUnit)")
        case .balance where account.currency != .twd:
            parts.append(Fmt.money(native, account.currency))
        case .balance:
            break
        case .portfolio:
            let n = snapshot.holdings[account.id]?.count ?? 0
            parts.append(n == 0 ? "尚未設定持股" : "\(n) 檔持股")
            if account.currency != .twd { parts.append(Fmt.money(native, account.currency)) }
        }
        if !account.note.isEmpty { parts.append(account.note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var change: some View {
        if let previous {
            let now = store.value(of: account, in: snapshot)
            let old = store.value(of: account, in: previous)
            if abs(now - old) < 1 {
                Text("持平").foregroundStyle(.tertiary)
            } else if abs(old) < 1 {
                Text("新增").foregroundStyle(.secondary)
            } else if account.category.isLiability {
                // 帳單變多不是「漲」，用中性色顯示應繳金額的變化。
                // 有退款（負數）時百分比沒意義，改顯示差額
                let owed = -now, owedBefore = -old
                Text("\(owed > owedBefore ? "▲" : "▼") " + (owed > 0 && owedBefore > 0
                     ? abs((owed - owedBefore) / owedBefore).formatted(.percent.precision(.fractionLength(1)))
                     : Fmt.money(abs(owed - owedBefore), .twd)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                DeltaText(delta: now - old, base: old, showPercentOnly: true)
            }
        }
    }
}

// MARK: - 帳戶明細

struct AccountDetailView: View {
    @Environment(\.portfolio) private var store
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var editing = false
    @State private var editingAmount = false

    /// 編輯後名稱等資料會更新，所以每次都從 store 取最新的
    private var current: Account { store.account(id: account.id) ?? account }

    private struct Row: Identifiable {
        let id: UUID
        let date: Date
        let amount: Double?
        let value: Double
        let delta: Double?
    }

    private var rows: [Row] {
        var result: [Row] = []
        var last: Double?
        for s in store.snapshots where s.amounts[account.id] != nil || last != nil {
            let v = abs(store.value(of: current, in: s))
            result.append(Row(id: s.id, date: s.date, amount: s.amounts[account.id], value: v,
                              delta: last.map { v - $0 }))
            last = v
        }
        return result.reversed()
    }

    var body: some View {
        let account = current
        List {
            Section {
                HStack(spacing: 14) {
                    AccountAvatar(account: account, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        // 會隨市場變動的帳戶顯示即時估值，和下方持股的即時股價一致
                        if let shown = (store.isMarketLinked(account) ? store.liveSnapshot : nil) ?? store.latest {
                            MoneyText(value: abs(store.value(of: account, in: shown)))
                                .font(.system(size: 30, weight: .regular))
                            if account.currency != .twd || account.valuation != .balance {
                                MoneyText(value: store.nativeValue(of: account, in: shown) ?? 0, currency: account.currency)
                                    .foregroundStyle(.secondary)
                            }
                            if shown.id == PortfolioStore.liveSnapshotID {
                                Label("即時估值", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                        if account.isArchived {
                            Label("已封存", systemImage: "archivebox").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)

                if rows.count > 1 {
                    Chart(rows.reversed()) { r in
                        LineMark(x: .value("日期", r.date), y: .value("金額", r.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(account.category.tint)
                        PointMark(x: .value("日期", r.date), y: .value("金額", r.value))
                            .foregroundStyle(account.category.tint)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXScale(range: .plotDimension(padding: 20))
                    .chartXAxis {
                        AxisMarks(values: rows.map(\.date)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), anchor: .top)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { v in
                            AxisGridLine()
                            AxisValueLabel { if let d = v.as(Double.self) { Text(store.hideAmounts ? "" : Fmt.wan(d)) } }
                        }
                    }
                    .frame(height: 180)
                    .padding(.vertical, 6)
                }
            }

            if account.isPortfolio, let latest = store.latest {
                PositionsSection(account: account, snapshot: latest)
            } else if account.category == .stocks, !account.isArchived {
                Section("持股") {
                    ConvertToPortfolioPrompt(accounts: [account])
                }
            }

            Section(account.category.isLiability ? "帳單紀錄" : "紀錄") {
                if !account.isPortfolio, !account.isArchived, store.latest != nil {
                    Button {
                        editingAmount = true
                    } label: {
                        Label(account.category.isLiability ? "輸入應繳金額" : "輸入金額", systemImage: "square.and.pencil")
                    }
                }
                ForEach(rows) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.date.formatted(.dateTime.year().month(.defaultDigits).day()))
                            if case .holding = account.valuation, let amount = r.amount, !store.hideAmounts {
                                Text("\(Fmt.number(amount)) \(account.inputUnit)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if account.category.isLiability && (r.amount ?? 0) == 0 {
                                Text("無帳單").foregroundStyle(.secondary)
                            } else {
                                MoneyText(value: r.value)
                            }
                            if let d = r.delta, abs(d) >= 1 {
                                if account.category.isLiability {
                                    Text(Fmt.signedMoney(d, .twd)).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    DeltaText(delta: d, base: r.value - d).font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            Section("資訊") {
                LabeledContent("分類", value: account.category.title)
                LabeledContent("幣別", value: account.currency.name)
                LabeledContent("計價方式", value: {
                    if case .holding(let q) = account.valuation { return "持有數量 × \(q.title)價格" }
                    if account.isPortfolio { return "持股明細（股數 × 即時股價）" }
                    return account.category.isLiability ? "輸入應繳金額" : "直接輸入餘額"
                }())
                NoteField(account: account)
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編輯") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            AccountEditor(account: account).environment(\.portfolio, store)
        }
        .sheet(isPresented: $editingAmount) {
            AmountEditor(account: account).environment(\.portfolio, store)
        }
        .onChange(of: store.account(id: account.id) == nil) { _, deleted in
            if deleted { dismiss() }
        }
    }
}

// MARK: - 備註

/// 帳戶頁的備註：直接點一下就能改，按 Return、點別處或離開頁面時自動儲存。
/// 沒有備註時也顯示，方便之後再補上
private struct NoteField: View {
    @Environment(\.portfolio) private var store
    let account: Account
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent("備註") {
            TextField("備註", text: $draft, prompt: Text("新增備註"), axis: .vertical)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(commit)
        }
        .onAppear { draft = account.note }
        // 在別的地方（例如「編輯」視窗）改了備註，這裡跟著更新
        .onChange(of: account.note) { _, new in if !focused { draft = new } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var a = store.account(id: account.id), a.note != trimmed else { return }
        a.note = trimmed
        store.update(a)
    }
}

// MARK: - 修改最新一筆紀錄中的金額

/// 直接修改某帳戶在某一筆紀錄中的金額（帳單、餘額或持有數量），不必走完整的更新流程。
/// 沒指定紀錄時改最新一筆（帳戶頁）；歷史紀錄裡改今天那筆時會傳入那一天的紀錄
struct AmountEditor: View {
    @Environment(\.portfolio) private var store
    @Environment(\.dismiss) private var dismiss
    let account: Account
    var target: Snapshot? = nil
    @State private var text = ""
    /// 帳戶備註：跟金額一起改，按「儲存」時一起存
    @State private var note = ""

    private var record: Snapshot? { target ?? store.latest }
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("金額", text: $text, prompt: Text("0"))
                            .focused($focused)
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Text(account.inputUnit).foregroundStyle(.secondary)
                    }
                } header: {
                    if let d = record?.date {
                        Text("\(d.formatted(.dateTime.year().month().day())) 的紀錄")
                    }
                } footer: {
                    Text(account.category.isLiability ? "這期信用卡帳單的應繳金額；有退款（溢繳）就填負數，例如 -500；沒有帳單就填 0。"
                         : target == nil ? "會更新最新一筆紀錄中這個帳戶的數字。" : "會更新這一天紀錄中這個帳戶的數字。")
                }

                Section {
                    TextField("備註", text: $note, prompt: Text("選填"), axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("備註")
                } footer: {
                    Text("帳戶的備註，所有紀錄共用。")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(account.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }.disabled(Fmt.parse(text) == nil)
                }
            }
            .onAppear {
                note = store.account(id: account.id)?.note ?? account.note
                if let v = record?.amounts[account.id] {
                    text = Fmt.number(v, digits: account.inputFractionDigits).replacingOccurrences(of: ",", with: "")
                }
                focused = true
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 360)
        #endif
    }

    private func save() {
        guard var s = record, let v = Fmt.parse(text) else { return }
        s.amounts[account.id] = v
        store.save(s)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if var a = store.account(id: account.id), a.note != trimmed {
            a.note = trimmed
            store.update(a)
        }
        dismiss()
    }
}

// MARK: - 新增／編輯帳戶

struct AccountEditor: View {
    @Environment(\.portfolio) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil 表示新增
    private let account: Account?
    /// 新增後回傳新帳戶（例如從更新畫面新增信用卡時，自動跳到該欄位）
    private let onCreate: ((Account) -> Void)?

    @State private var name: String
    @State private var note: String
    @State private var category: AssetCategory
    @State private var currency: Currency
    @State private var holding: Quote?
    /// 股票帳戶：記錄每檔股數，股價自動更新
    @State private var usesPortfolio: Bool
    /// 現金子分類；nil 為自動判斷
    @State private var cashGroup: CashGroup?
    /// 負債：這期的結帳日、繳費日（打開時已過期的會帶到下個月同一天）
    @State private var statementDate: Date?
    @State private var dueDate: Date?
    /// 打開時的值，用來判斷有沒有改過（沒改就保留原本存的日期）
    @State private var initialStatementDate: Date?
    @State private var initialDueDate: Date?
    /// 打開時就已經自動帶到下個月、需要確認的項目
    @State private var rolledKinds: Set<BillEvent.Kind> = []
    /// 和同銀行的卡共用日期
    @State private var shareBillDates: Bool
    /// 負債種類與貸款設定
    @State private var liabilityType: LiabilityType
    @State private var loanDay: Int?
    @State private var loanPaymentText: String
    @State private var loanHasStart: Bool
    @State private var loanStart: Date
    /// 信用卡：自動扣款
    @State private var autoDebit: Bool
    /// 貸款：預約轉帳設定到哪天、轉入哪個帳戶
    @State private var loanScheduled: Bool
    @State private var loanScheduledUntil: Date
    @State private var loanTransferAccount: UUID?
    @State private var confirmDelete = false

    // 圖示
    @State private var draftID: UUID
    @State private var iconChoice: IconChoice
    @State private var domain: String
    @State private var tokenID: String
    @State private var region: String
    @State private var pendingImage: Data?
    @State private var pickingImage = false

    enum IconChoice: String, CaseIterable, Identifiable {
        case auto, website, token, flag, custom, monogram
        var id: Self { self }
        var title: String {
            switch self {
            case .auto: "自動"
            case .website: "網站圖示"
            case .token: "代幣"
            case .flag: "國旗"
            case .custom: "自訂圖片"
            case .monogram: "文字縮寫"
            }
        }
    }

    init(account: Account? = nil, category: AssetCategory = .cash, onCreate: ((Account) -> Void)? = nil) {
        self.account = account
        self.onCreate = onCreate
        _draftID = State(initialValue: account?.id ?? UUID())
        let suggested = account.map(IconCatalog.suggestion) ?? .monogram
        var choice = IconChoice.auto
        var domain = "", token = "bitcoin", region = IconCatalog.region(for: account?.currency ?? .twd)
        for icon in [suggested, account?.icon].compactMap({ $0 }) {
            switch icon {
            case .website(let d): domain = d
            case .token(let id): token = id
            case .flag(let r): region = r
            default: break
            }
        }
        switch account?.icon {
        case .website?: choice = .website
        case .token?: choice = .token
        case .flag?: choice = .flag
        case .custom?: choice = .custom
        case .monogram?: choice = .monogram
        case nil: choice = .auto
        }
        _iconChoice = State(initialValue: choice)
        _domain = State(initialValue: domain)
        _tokenID = State(initialValue: token)
        _region = State(initialValue: region)
        _name = State(initialValue: account?.name ?? "")
        _note = State(initialValue: account?.note ?? "")
        _category = State(initialValue: account?.category ?? category)
        _currency = State(initialValue: account?.currency ?? .twd)
        _usesPortfolio = State(initialValue: account.map(\.isPortfolio) ?? (category == .stocks))
        _cashGroup = State(initialValue: account?.cashGroup)
        _shareBillDates = State(initialValue: account?.sharesBillDates ?? true)
        _liabilityType = State(initialValue: account?.resolvedLiabilityType ?? .card)
        _loanDay = State(initialValue: account?.loanPaymentDay)
        _loanPaymentText = State(initialValue: account?.loanMonthlyPayment.map { Fmt.number($0, digits: 0...2).replacingOccurrences(of: ",", with: "") } ?? "")
        _loanHasStart = State(initialValue: account?.loanStartDate != nil)
        _loanStart = State(initialValue: account?.loanStartDate ?? .now)
        _autoDebit = State(initialValue: account?.autoDebit ?? false)
        _loanScheduled = State(initialValue: account?.paymentScheduledUntil != nil)
        _loanScheduledUntil = State(initialValue: account?.paymentScheduledUntil ?? .now)
        _loanTransferAccount = State(initialValue: account?.paymentAccountID)
        if case .holding(let q) = account?.valuation {
            _holding = State(initialValue: q)
        } else {
            _holding = State(initialValue: nil)
        }
    }

    private var isNew: Bool { account == nil }

    private var normalizedDomain: String {
        var d = domain.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["https://", "http://"] where d.hasPrefix(prefix) { d.removeFirst(prefix.count) }
        return String(d.split(separator: "/").first ?? "")
    }

    private var resolvedIcon: AccountIcon? {
        switch iconChoice {
        case .auto: nil
        case .website: normalizedDomain.isEmpty ? nil : .website(domain: normalizedDomain)
        case .token: .token(id: tokenID)
        case .flag: .flag(region: region)
        case .custom: (pendingImage != nil || account?.icon == .custom) ? .custom : nil
        case .monogram: .monogram
        }
    }

    /// 用目前填的內容組出帳戶，給頭像預覽與自動配對使用
    private func draftAccount(icon: AccountIcon?) -> Account {
        let liability = category.isLiability
        return Account(id: draftID, name: trimmedName.isEmpty ? category.title : trimmedName, note: note,
                       category: category,
                       currency: account?.currency ?? ((holding == nil || liability) ? currency : .usd),
                       valuation: account?.valuation ?? (liability ? .balance
                           : (category == .stocks && usesPortfolio) ? .portfolio
                           : (holding.map { .holding(quote: $0) } ?? .balance)),
                       icon: icon)
    }

    private var iconSection: some View {
        Section {
            HStack(spacing: 16) {
                AccountAvatar(account: draftAccount(icon: resolvedIcon), size: 56,
                              preview: iconChoice == .custom ? pendingImage.flatMap(PlatformImage.init(data:)) : nil)
                Picker("圖示", selection: $iconChoice) {
                    ForEach(IconChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            switch iconChoice {
            case .website:
                TextField("網站", text: $domain, prompt: Text("例如：www.esunbank.com"))
                    .autocorrectionDisabled()
                Button("重新下載圖示") {
                    IconLoader.shared.refresh(.website(domain: normalizedDomain), accountID: draftID)
                }
                .disabled(normalizedDomain.isEmpty)
            case .token:
                Picker("代幣", selection: $tokenID) {
                    ForEach(IconCatalog.tokens, id: \.id) { Text($0.symbol).tag($0.id) }
                }
            case .flag:
                Picker("國旗", selection: $region) {
                    ForEach(IconCatalog.flags, id: \.region) { f in
                        Text("\(IconCatalog.flagEmoji(f.region)) \(f.name)").tag(f.region)
                    }
                }
            case .custom:
                Button(pendingImage == nil && account?.icon != .custom ? "選擇圖片…" : "更換圖片…") { pickingImage = true }
            case .auto, .monogram:
                EmptyView()
            }
        } header: {
            Text("圖示")
        } footer: {
            switch iconChoice {
            case .auto:
                Text("依名稱自動配對：\(IconCatalog.describe(IconCatalog.suggestion(for: draftAccount(icon: nil))))")
            case .website:
                Text("從銀行或交易所網站下載圖示並存在本機。圖示不清楚的話，可以改用自訂圖片。")
            case .custom:
                Text("建議使用正方形圖片，例如從 App Store 存下的 App 圖示。")
            default:
                EmptyView()
            }
        }
        .fileImporter(isPresented: $pickingImage, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingImage = try? Data(contentsOf: url)
        }
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱", text: $name, prompt: Text(category.namePrompt))
                    TextField("備註", text: $note, prompt: Text(category.isLiability ? "選填，例如：每月 15 號結帳" : "選填"))
                }

                if category.isLiability {
                    Section {
                        Picker("類型", selection: $liabilityType) {
                            ForEach(LiabilityType.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(liabilityType == .loan ? "貸款每月固定日期扣款；帳戶金額填剩餘本金。" : "信用卡每期的結帳日、繳費日可能因假日不同。")
                    }
                }

                if category.isLiability && liabilityType == .loan {
                    Section {
                        Picker("每月扣款日", selection: $loanDay) {
                            Text("不設定").tag(Int?.none)
                            ForEach(1...31, id: \.self) { d in Text("每月 \(d) 號").tag(Int?.some(d)) }
                        }
                        HStack {
                            Text("每月繳款金額")
                            Spacer()
                            TextField("每月繳款金額", text: $loanPaymentText, prompt: Text("選填"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(maxWidth: 140)
                            Text(currency.rawValue).foregroundStyle(.secondary)
                        }
                        Toggle("目前還不需繳費", isOn: $loanHasStart)
                        if loanHasStart {
                            DatePicker("開始繳費日期", selection: $loanStart, displayedComponents: .date)
                        }
                        Toggle("自動扣款", isOn: $autoDebit)
                        if !autoDebit {
                            Toggle("已設定預約轉帳", isOn: $loanScheduled)
                            if loanScheduled {
                                DatePicker("設定到", selection: $loanScheduledUntil, displayedComponents: .date)
                                Picker("轉入帳戶", selection: $loanTransferAccount) {
                                    Text("不指定").tag(UUID?.none)
                                    ForEach(store.activeAccounts(in: .cash)) { a in Text(a.name).tag(UUID?.some(a.id)) }
                                }
                            }
                        }
                    } header: {
                        Text("還款")
                    } footer: {
                        Text("會顯示在總覽的「繳費與結帳」和月曆上。還在寬限期的話，打開「目前還不需繳費」並填開始繳費的日期。預約轉帳設定到的日期之後，總覽會提醒你再設定。")
                    }
                }

                if category.isLiability && liabilityType == .card {
                    Section {
                        if let account, account.bankDomain != nil {
                            Toggle(isOn: $shareBillDates) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("和同一間銀行的卡共用日期")
                                    if !bankMates.isEmpty {
                                        Text("一起設定：" + bankMates.map(\.name).joined(separator: "、"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        billDateRow("繳費日", kind: .due, date: $dueDate)
                        billDateRow("結帳日", kind: .statement, date: $statementDate)
                        Toggle(isOn: $autoDebit) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自動扣款")
                                Text(autoDebit ? "從銀行帳戶自動扣，每期都不用另外處理"
                                               : "沒有自動扣款：每期要在繳費日前設定預約轉帳，總覽會提醒")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("結帳與繳費")
                    } footer: {
                        Text("選填，填這一期的日期。過了之後會自動帶到下個月同一天，遇到假日不同再改。會顯示在總覽的「接下來要繳」和月曆上；貸款的扣款日填在繳費日。")
                    }
                }

                Section {
                    Picker("分類", selection: $category) {
                        ForEach(AssetCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if category == .cash {
                        Picker("子分類", selection: $cashGroup) {
                            Text("自動").tag(CashGroup?.none)
                            ForEach(CashGroup.allCases) { Label($0.title, systemImage: $0.symbol).tag(CashGroup?.some($0)) }
                        }
                    }
                    if category == .stocks && (isNew || account?.valuation == .balance) {
                        Picker("計價方式", selection: $usesPortfolio) {
                            Text("持股明細（自動更新股價）").tag(true)
                            Text("輸入總金額").tag(false)
                        }
                    }
                    if isNew {
                        if !category.isLiability && category != .stocks {
                            Picker("計價方式", selection: $holding) {
                                Text("輸入餘額").tag(Quote?.none)
                                ForEach(Quote.holdable) { q in
                                    Text("持有 \(q.assetSymbol ?? "") 數量").tag(Quote?.some(q))
                                }
                            }
                        }
                        if holding == nil || category.isLiability {
                            Picker("幣別", selection: $currency) {
                                ForEach(Currency.allCases) { Text("\($0.name)（\($0.rawValue)）").tag($0) }
                            }
                        }
                    } else if let account {
                        LabeledContent("幣別", value: account.currency.name)
                        if !(category == .stocks && account.valuation == .balance) {
                            LabeledContent("計價方式", value: account.isPortfolio ? "持股明細"
                                           : holding.map { "持有 \($0.assetSymbol ?? "") 數量" } ?? "輸入餘額")
                        }
                    }
                } footer: {
                    if category == .stocks && usesPortfolio && account?.valuation == .balance {
                        Text("改成持股明細後，過去的紀錄不變。下次「更新資產」時加入股票代號與股數，股價就會自動更新。")
                    } else if category == .stocks && usesPortfolio && isNew {
                        Text("記錄每檔股票的股數，市值會依即時股價自動計算。股數只有買賣時才需要改。")
                    } else if !isNew {
                        Text("幣別與計價方式建立後無法更改，以免影響過去的紀錄。")
                    } else if category.isLiability {
                        Text("每次更新時輸入本期應繳金額，計算淨值時會自動扣除；有退款就填負數。沒有帳單的那期留空即可。")
                    } else if holding != nil {
                        Text("每次更新時輸入持有數量，App 會自動乘上當時的價格。")
                    } else {
                        Text("每次更新時輸入帳戶餘額。")
                    }
                }

                iconSection

                if let account {
                    Section {
                        Button(account.isArchived ? "取消封存" : "封存") {
                            store.setArchived(account, !account.isArchived)
                            dismiss()
                        }
                        Button("刪除", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("封存：不再出現在更新畫面，但保留過去的紀錄。\n刪除：連同過去所有紀錄一起移除，淨資產歷史會跟著改變。")
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear(perform: loadBillDates)
            .navigationTitle(isNew ? category.addTitle : "編輯「\(account?.name ?? "")」")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "新增" : "完成") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("刪除「\(account?.name ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除帳戶與所有紀錄", role: .destructive) {
                    if let account { store.delete(account) }
                    dismiss()
                }
                if let account, !account.isArchived {
                    Button("改為封存") {
                        store.setArchived(account, true)
                        dismiss()
                    }
                }
            } message: {
                let count = account.map(store.recordCount) ?? 0
                Text(count > 0
                     ? "這個帳戶出現在 \(count) 筆紀錄中，刪除後這些金額也會移除，無法復原。如果只是不再使用，建議改為封存。"
                     : "這個動作無法復原。")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: isNew ? 380 : 460)
        #endif
    }

    /// 打開編輯時載入日期：用整組（同銀行共用）的日期；已經過了的帶到下一次（同一天），並提醒確認
    private func loadBillDates() {
        guard let account, account.category.isLiability else { return }
        var rolled: Set<BillEvent.Kind> = []
        func upcoming(_ kind: BillEvent.Kind) -> Date? {
            guard let set = account.sharesBillDates ? store.groupBillDate(kind, for: account) : account.billDate(kind)
            else { return nil }
            if Calendar.current.startOfDay(for: set.date) >= Calendar.current.startOfDay(for: .now) { return set.date }
            var probe = account
            if kind == .due { probe.dueDate = set } else { probe.statementDate = set }
            let next = probe.billEvents(from: .now, within: 62).first { $0.kind == kind }
            if next != nil { rolled.insert(kind) }
            return next?.date ?? set.date
        }
        let s = upcoming(.statement), d = upcoming(.due)
        statementDate = s; dueDate = d
        initialStatementDate = s; initialDueDate = d
        rolledKinds = rolled
    }

    /// 同銀行、會一起共用日期的其他卡（顯示在開關下方）
    private var bankMates: [Account] {
        guard let account, let bank = account.bankDomain else { return [] }
        return store.activeAccounts(in: .liability).filter { $0.id != account.id && $0.bankDomain == bank && $0.sharesBillDates }
    }

    /// 開關打開才顯示日期選擇；已自動帶到下個月的，提醒確認是不是同一天
    @ViewBuilder private func billDateRow(_ title: String, kind: BillEvent.Kind, date: Binding<Date?>) -> some View {
        Toggle(title, isOn: Binding(get: { date.wrappedValue != nil },
                                    set: { date.wrappedValue = $0 ? (date.wrappedValue ?? .now) : nil }))
        if let value = date.wrappedValue {
            DatePicker("這期\(title)", selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                       displayedComponents: .date)
            if rolledKinds.contains(kind), value == (kind == .due ? initialDueDate : initialStatementDate) {
                Label("已經是下個月了，日期先帶到同一天，請確認是否正確", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// 負債種類與貸款設定寫回帳戶（種類和名稱判斷一致時存 nil，之後改名仍會自動判斷）
    private func applyLoanSettings(to a: inout Account) {
        a.liabilityType = nil
        if a.resolvedLiabilityType != liabilityType { a.liabilityType = liabilityType }
        if liabilityType == .loan {
            a.loanPaymentDay = loanDay
            a.loanMonthlyPayment = Fmt.parse(loanPaymentText)
            a.loanStartDate = loanHasStart ? Calendar.current.startOfDay(for: loanStart) : nil
            a.autoDebit = autoDebit ? true : nil
            a.paymentScheduledUntil = !autoDebit && loanScheduled ? Calendar.current.startOfDay(for: loanScheduledUntil) : nil
            a.paymentAccountID = !autoDebit && loanScheduled ? loanTransferAccount : nil
            a.statementDate = nil
            a.dueDate = nil
        }
    }

    /// 沒改過就保留原本存的日期（還沒確認的自動帶入不會因為改了名稱就被當成已確認）
    private func resolvedBillDate(_ value: Date?, initial: Date?, stored: BillDate?) -> BillDate? {
        guard let value else { return nil }
        if value == initial, let stored { return stored }
        return BillDate(date: value)
    }

    private func save() {
        if iconChoice == .custom, let pendingImage {
            try? IconLoader.shared.setCustom(pendingImage, accountID: draftID)
        }
        if var a = account {
            a.name = trimmedName
            a.note = note
            a.category = category
            a.cashGroup = category == .cash ? cashGroup : nil
            a.statementDate = category.isLiability
                ? resolvedBillDate(statementDate, initial: initialStatementDate, stored: a.statementDate) : nil
            a.dueDate = category.isLiability
                ? resolvedBillDate(dueDate, initial: initialDueDate, stored: a.dueDate) : nil
            a.shareBillDates = category.isLiability && shareBillDates != a.sharesBillDates ? shareBillDates : a.shareBillDates
            if category.isLiability { applyLoanSettings(to: &a) }
            a.icon = resolvedIcon
            if a.category == .stocks && a.valuation == .balance && usesPortfolio {
                a.valuation = .portfolio
            }
            store.update(a)
            // 自動扣款：同銀行共用日期的卡一起改
            if a.category.isLiability && !a.isLoan && autoDebit != (account?.autoDebit ?? false) {
                if a.sharesBillDates { store.setAutoDebit(autoDebit, for: a.id) }
                else if var b = store.account(id: a.id) { b.autoDebit = autoDebit ? true : nil; store.update(b) }
            }
            // 改了日期：同銀行共用日期的卡一起改
            if a.category.isLiability && a.sharesBillDates {
                if dueDate != initialDueDate { store.setBillDate(dueDate, kind: .due, for: a.id) }
                if statementDate != initialStatementDate { store.setBillDate(statementDate, kind: .statement, for: a.id) }
            }
        } else {
            var a = draftAccount(icon: resolvedIcon)
            a.name = trimmedName
            a.cashGroup = category == .cash ? cashGroup : nil
            a.statementDate = category.isLiability ? statementDate.map(BillDate.init) : nil
            a.dueDate = category.isLiability ? dueDate.map(BillDate.init) : nil
            a.autoDebit = category.isLiability && autoDebit ? true : nil
            if category.isLiability { applyLoanSettings(to: &a) }
            store.add(a)
            onCreate?(a)
        }
        dismiss()
    }
}
