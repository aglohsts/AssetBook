import SwiftUI

// MARK: - 幣別

enum Currency: String, CaseIterable, Identifiable, Codable, Hashable {
    case twd = "TWD", usd = "USD", jpy = "JPY", gbp = "GBP"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .twd: "NT$"
        case .usd: "US$"
        case .jpy: "¥"
        case .gbp: "£"
        }
    }

    var name: String {
        switch self {
        case .twd: "新台幣"
        case .usd: "美元"
        case .jpy: "日圓"
        case .gbp: "英鎊"
        }
    }

    var fractionDigits: Int { self == .usd || self == .gbp ? 2 : 0 }

    var tint: Color {
        switch self {
        case .twd: .indigo
        case .usd: .teal
        case .jpy: .pink
        case .gbp: .purple
        }
    }
}

// MARK: - 資產分類

enum AssetCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case crypto, stocks, cash, liability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crypto: "加密貨幣"
        case .stocks: "股票"
        case .cash: "現金與存款"
        case .liability: "負債"
        }
    }

    var symbol: String {
        switch self {
        case .crypto: "bitcoinsign.circle.fill"
        case .stocks: "chart.line.uptrend.xyaxis.circle.fill"
        case .cash: "banknote.fill"
        case .liability: "creditcard.fill"
        }
    }

    var tint: Color {
        switch self {
        case .crypto: .orange
        case .stocks: .blue
        case .cash: .green
        case .liability: .red
        }
    }

    /// 負債以正數輸入（應繳金額），計算淨值時扣除。
    var isLiability: Bool { self == .liability }

    /// 新增按鈕上的文字
    var addTitle: String { self == .liability ? "新增信用卡" : "新增帳戶" }

    var namePrompt: String {
        switch self {
        case .crypto: "例如：Binance"
        case .stocks: "例如：富邦證券"
        case .cash: "例如：玉山銀行"
        case .liability: "例如：國泰 CUBE 卡"
        }
    }
}

// MARK: - 市場報價

/// 每次更新時需要填的報價：匯率（以台幣計）與加密貨幣價格（以美元計）。
enum Quote: String, CaseIterable, Identifiable, Codable, Hashable {
    case usdTWD, jpyTWD, gbpTWD, btcUSD, croUSD

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usdTWD: "美元匯率"
        case .jpyTWD: "日圓匯率"
        case .gbpTWD: "英鎊匯率"
        case .btcUSD: "比特幣"
        case .croUSD: "Cronos"
        }
    }

    var unit: String {
        switch self {
        case .usdTWD: "TWD/USD"
        case .jpyTWD: "TWD/JPY"
        case .gbpTWD: "TWD/GBP"
        case .btcUSD, .croUSD: "USD"
        }
    }

    /// 以這個報價計價的資產代號（數量 × 價格）。
    var assetSymbol: String? {
        switch self {
        case .btcUSD: "BTC"
        case .croUSD: "CRO"
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .usdTWD: "dollarsign.circle"
        case .jpyTWD: "yensign.circle"
        case .gbpTWD: "sterlingsign.circle"
        case .btcUSD: "bitcoinsign.circle"
        case .croUSD: "c.circle"
        }
    }

    /// 自動帶入報價時保留的小數位數
    var liveFractionDigits: Int {
        switch self {
        case .usdTWD: 4
        case .jpyTWD: 6
        case .gbpTWD: 4
        case .btcUSD: 0
        case .croUSD: 5
        }
    }

    /// 顯示用的小數位數（存檔仍保留完整精度）
    var displayDigits: Int {
        switch self {
        case .usdTWD: 3
        case .jpyTWD: 4
        case .gbpTWD: 3
        case .btcUSD: 0
        case .croUSD: 5
        }
    }

    /// 顯示用的前綴：幣價以美元計
    var displayPrefix: String { assetSymbol == nil ? "" : "US$" }

    static var holdable: [Quote] { allCases.filter { $0.assetSymbol != nil } }
}

// MARK: - 帳戶

enum Valuation: Codable, Hashable {
    /// 直接輸入餘額（以帳戶幣別計）。
    case balance
    /// 輸入持有數量，價值 = 數量 × 報價（美元）。
    case holding(quote: Quote)
    /// 股票持股明細：價值 = Σ 股數 × 股價 ＋ 帳戶現金
    case portfolio
}

/// 現金與存款的子分類
enum CashGroup: String, Codable, CaseIterable, Identifiable, Hashable {
    case bank, exchange, wallet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank: "銀行存款"
        case .exchange: "交易所與穩定幣"
        case .wallet: "現鈔與儲值"
        }
    }

    var symbol: String {
        switch self {
        case .bank: "building.columns"
        case .exchange: "arrow.left.arrow.right"
        case .wallet: "wallet.bifold"
        }
    }
}

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var note: String
    var category: AssetCategory
    var currency: Currency
    var valuation: Valuation
    /// 封存：不再出現在更新畫面與帳戶列表，但保留歷史紀錄
    var isArchived: Bool
    /// nil 表示依名稱自動配對（見 IconCatalog）
    var icon: AccountIcon?
    /// 現金帳戶的子分類；nil 表示依名稱與備註自動判斷
    var cashGroup: CashGroup?
    /// 負債：結帳日、繳費日（或扣款日）。存的是實際日期，過了之後自動帶到下個月同一天、等使用者確認
    var statementDate: BillDate?
    var dueDate: BillDate?
    /// 和同一間銀行的其他卡共用結帳日、繳費日；nil 表示自動（名稱有「未出帳」的不共用）
    var shareBillDates: Bool?
    /// 負債的種類：信用卡或貸款；nil 表示依名稱判斷（有「貸」的是貸款）
    var liabilityType: LiabilityType?
    /// 貸款：每月幾號扣款、每月繳多少（帳戶金額是剩餘本金，不是每月要繳的錢）、從哪天開始繳（寬限期）
    var loanPaymentDay: Int?
    var loanMonthlyPayment: Double?
    var loanStartDate: Date?
    /// 信用卡：從銀行帳戶自動扣款（每期都不用處理）
    var autoDebit: Bool?
    /// 信用卡：已設定預約轉帳（外幣卡是已換匯）的那一期繳費日；過了那期就要重新設定
    var paymentScheduledFor: Date?
    /// 貸款：預約轉帳已經一路設定到哪一天、轉入哪個帳戶
    var paymentScheduledUntil: Date?
    var paymentAccountID: UUID?

    init(id: UUID = UUID(), name: String, note: String = "", category: AssetCategory,
         currency: Currency, valuation: Valuation = .balance, isArchived: Bool = false,
         icon: AccountIcon? = nil, cashGroup: CashGroup? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.category = category
        self.currency = currency
        self.valuation = valuation
        self.isArchived = isArchived
        self.icon = icon
        self.cashGroup = cashGroup
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, category, currency, valuation, isArchived, icon, cashGroup, statementDate, dueDate, shareBillDates,
             liabilityType, loanPaymentDay, loanMonthlyPayment, loanStartDate, autoDebit, paymentScheduledFor,
             paymentScheduledUntil, paymentAccountID
    }

    // 舊版資料檔沒有 isArchived，預設為 false
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        category = try c.decode(AssetCategory.self, forKey: .category)
        currency = try c.decode(Currency.self, forKey: .currency)
        valuation = try c.decode(Valuation.self, forKey: .valuation)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        icon = try c.decodeIfPresent(AccountIcon.self, forKey: .icon)
        cashGroup = try c.decodeIfPresent(CashGroup.self, forKey: .cashGroup)
        statementDate = try c.decodeIfPresent(BillDate.self, forKey: .statementDate)
        dueDate = try c.decodeIfPresent(BillDate.self, forKey: .dueDate)
        shareBillDates = try c.decodeIfPresent(Bool.self, forKey: .shareBillDates)
        liabilityType = try c.decodeIfPresent(LiabilityType.self, forKey: .liabilityType)
        loanPaymentDay = try c.decodeIfPresent(Int.self, forKey: .loanPaymentDay)
        loanMonthlyPayment = try c.decodeIfPresent(Double.self, forKey: .loanMonthlyPayment)
        loanStartDate = try c.decodeIfPresent(Date.self, forKey: .loanStartDate)
        autoDebit = try c.decodeIfPresent(Bool.self, forKey: .autoDebit)
        paymentScheduledFor = try c.decodeIfPresent(Date.self, forKey: .paymentScheduledFor)
        paymentScheduledUntil = try c.decodeIfPresent(Date.self, forKey: .paymentScheduledUntil)
        paymentAccountID = try c.decodeIfPresent(UUID.self, forKey: .paymentAccountID)
    }

    /// 子分類：自己選的優先，否則看名稱與備註猜（穩定幣、交易所 → 交易所；現金、儲值卡 → 現鈔與儲值）
    var resolvedCashGroup: CashGroup {
        if let cashGroup { return cashGroup }
        let text = (name + " " + note).lowercased()
        let exchange = ["穩定幣", "交易所", "usdc", "usdt", "kraken", "binance", "coinbase", "okx", "bitopro", "max"]
        let wallet = ["現金", "現鈔", "suica", "pasmo", "icoca", "悠遊卡", "一卡通", "paypay", "儲值", "錢包"]
        if exchange.contains(where: text.contains) { return .exchange }
        if wallet.contains(where: text.contains) { return .wallet }
        return .bank
    }

    /// 頭像上的字：持有幣種用代號（BTC），短的英文縮寫整個顯示（USDC），其他取第一個字（樂、K）
    var monogram: String {
        if case .holding(let q) = valuation, let s = q.assetSymbol { return s }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 4, trimmed.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }), !trimmed.isEmpty {
            return trimmed
        }
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    /// 輸入欄位的單位，例如「CRO」、「USD」。
    var inputUnit: String {
        if case .holding(let q) = valuation, let s = q.assetSymbol { return s }
        return currency.rawValue
    }

    var inputFractionDigits: ClosedRange<Int> {
        if case .holding = valuation { return 0...8 }
        return 0...currency.fractionDigits
    }

    var isPortfolio: Bool {
        if case .portfolio = valuation { return true }
        return false
    }
}

// MARK: - 快照（每次更新的一欄）

/// 一檔持股
struct Position: Codable, Hashable, Identifiable {
    var id: String { symbol }
    /// Yahoo 格式代號，例如 2330.TW、NVDA
    var symbol: String
    var name: String
    var shares: Double
}

struct Snapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var quotes: [Quote: Double]
    /// 帳戶 id → 餘額、持有數量，或持股帳戶的現金
    var amounts: [UUID: Double]
    /// 持股帳戶 id → 當時的持股
    var holdings: [UUID: [Position]]
    /// 代號 → 當時的股價（以該股票的幣別計）
    var stockPrices: [String: Double]

    init(id: UUID = UUID(), date: Date, quotes: [Quote: Double], amounts: [UUID: Double],
         holdings: [UUID: [Position]] = [:], stockPrices: [String: Double] = [:]) {
        self.id = id
        self.date = date
        self.quotes = quotes
        self.amounts = amounts
        self.holdings = holdings
        self.stockPrices = stockPrices
    }
}

// MARK: - 結帳日與繳費日

/// 負債的種類：信用卡（每期結帳、繳費日會變）或貸款（每月固定扣款）
enum LiabilityType: String, Codable, CaseIterable, Identifiable {
    case card, loan
    var id: Self { self }
    var title: String { self == .card ? "信用卡" : "貸款" }
    var symbol: String { self == .card ? "creditcard" : "building.columns" }
}

/// 使用者設定的一個實際日期（例如這期 12/3 繳費）。遇到假日可能提早或延後，所以存日期而不是「每月幾號」
struct BillDate: Codable, Hashable {
    var date: Date
}

/// 繳費前要處理的一件事：台幣是設定預約轉帳，外幣是換匯（例如日幣卡要先換日幣）
struct PaymentTask: Hashable, Identifiable {
    let currency: Currency
    let done: Bool
    /// 貸款：預約轉帳設定到哪一天、轉入哪個帳戶
    var scheduledUntil: Date? = nil
    var transferTo: String? = nil
    var id: Currency { currency }
    var doneTitle: String { currency == .twd ? "已設定預約轉帳" : "已換匯\(currency.casualName)" }
    var pendingTitle: String { currency == .twd ? "尚未設定預約轉帳" : "尚未換匯\(currency.casualName)" }
}

/// 某一期繳費的狀態
enum PaymentStatus: Equatable {
    /// 自動扣款，不用處理
    case autoDebit
    /// 本期沒有要繳的金額（0、留空或退款），不用處理
    case nothingDue
    /// 要處理的事（每個幣別一件），各自完成或還沒
    case tasks([PaymentTask])

    var pendingCount: Int {
        if case .tasks(let t) = self { return t.filter { !$0.done }.count }
        return 0
    }
}

extension Currency {
    /// 口語的幣別名稱，例如「日幣」
    var casualName: String {
        switch self {
        case .twd: "台幣"
        case .usd: "美金"
        case .jpy: "日幣"
        case .gbp: "英鎊"
        }
    }
}

/// 負債帳戶的一個結帳日或繳費日。同一間銀行共用日期的卡合成一筆（accounts 有多個）
struct BillEvent: Identifiable, Hashable {
    enum Kind: String { case statement, due }
    /// 代表的帳戶（顯示圖示、確認日期時用）
    let account: Account
    /// 共用這個日期的所有帳戶
    var accounts: [Account]
    let kind: Kind
    let date: Date
    /// 從上次設定的日期自動帶到之後的月份（同一天），還沒確認過；遇到假日可能不同
    let needsConfirm: Bool
    /// 貸款：每月繳款金額（帳戶本身的金額是剩餘本金）
    var loanPayment: Double? = nil
    var id: String { "\(account.id)-\(kind.rawValue)-\(date.timeIntervalSince1970)" }
    /// 月曆上的短字
    var shortTitle: String { kind == .due ? "繳" : "結" }
    var title: String { kind == .due ? (account.isLoan ? "扣款" : "繳費") : "結帳" }
    /// 一張卡用帳戶名稱；同銀行多張卡用銀行名稱
    var name: String { accounts.count > 1 ? (account.bankName ?? account.name) : account.name }
    /// 同銀行多張卡時，列出各張卡的名稱（去掉銀行名稱比較短）
    var memberNames: String? {
        guard accounts.count > 1 else { return nil }
        let bank = account.bankName ?? ""
        return accounts.map { a in
            let short = a.name.replacingOccurrences(of: bank, with: "").trimmingCharacters(in: .whitespaces)
            return short.isEmpty ? a.name : short
        }.joined(separator: "、")
    }
}

extension Calendar {
    /// 某個月的第 day 號；月份沒有那一天（例如 2 月 30 號）就用月底
    func date(day: Int, inMonthOf month: Date) -> Date? {
        guard let start = dateInterval(of: .month, for: month)?.start,
              let count = range(of: .day, in: .month, for: month)?.count else { return nil }
        return date(byAdding: .day, value: min(max(day, 1), count) - 1, to: start)
    }
}

extension Account {
    func billDate(_ kind: BillEvent.Kind) -> BillDate? { kind == .due ? dueDate : statementDate }

    /// 負債種類：自己選的優先，否則名稱有「貸」的是貸款
    var resolvedLiabilityType: LiabilityType { liabilityType ?? (name.contains("貸") ? .loan : .card) }
    var isLoan: Bool { category.isLiability && resolvedLiabilityType == .loan }

    /// 是否和同銀行的卡共用日期（預設：名稱有「未出帳」的不共用；貸款不共用）
    var sharesBillDates: Bool { !isLoan && (shareBillDates ?? !name.contains("未出帳")) }

    /// 貸款：還沒開始繳（寬限期中）
    func loanNotStarted(asOf date: Date = .now) -> Bool {
        guard isLoan, let start = loanStartDate else { return false }
        return Calendar.current.startOfDay(for: start) > Calendar.current.startOfDay(for: date)
    }

    /// 貸款：from 起 within 天內的每月扣款日（固定日期，不用確認；開始繳費日之前不算）
    func loanEvents(from: Date, within days: Int, calendar cal: Calendar = .current) -> [BillEvent] {
        guard isLoan, let day = loanPaymentDay else { return [] }
        var start = cal.startOfDay(for: from)
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        if let s = loanStartDate { start = max(start, cal.startOfDay(for: s)) }
        var out: [BillEvent] = []
        var month = start
        for _ in 0..<24 {
            guard let d = cal.date(day: day, inMonthOf: month) else { break }
            if d > end { break }
            if d >= start {
                out.append(BillEvent(account: self, accounts: [self], kind: .due, date: d, needsConfirm: false,
                                     loanPayment: loanMonthlyPayment))
            }
            guard let next = cal.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return out
    }

    /// 負債帳戶所屬的銀行（依圖示或名稱比對到的銀行網站）；認不出來就是 nil
    var bankDomain: String? {
        guard category.isLiability else { return nil }
        if case .website(let d) = icon ?? IconCatalog.suggestion(for: self) { return d }
        return nil
    }

    /// 銀行的簡稱，例如「玉山」
    var bankName: String? { bankDomain.flatMap { d in IconCatalog.sites.first { $0.domain == d }?.keywords.first } }

    /// from 當天起 within 天內的結帳日、繳費日。設定的日期本身算已確認；
    /// 之後的月份用同一天自動帶入，標成「需要確認」
    func billEvents(from: Date, within days: Int, calendar cal: Calendar = .current) -> [BillEvent] {
        let start = cal.startOfDay(for: from)
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        var out: [BillEvent] = []
        for kind in [BillEvent.Kind.statement, .due] {
            guard let set = billDate(kind) else { continue }
            func event(_ d: Date, _ needsConfirm: Bool) -> BillEvent {
                BillEvent(account: self, accounts: [self], kind: kind, date: d, needsConfirm: needsConfirm)
            }
            let base = cal.startOfDay(for: set.date)
            let day = cal.component(.day, from: base)
            if base >= start && base <= end {
                out.append(event(base, false))
            }
            var month = base
            for _ in 0..<120 {
                guard let next = cal.date(byAdding: .month, value: 1, to: month),
                      let d = cal.date(day: day, inMonthOf: next) else { break }
                month = next
                if d > end { break }
                if d >= start { out.append(event(d, true)) }
            }
        }
        return out
    }
}
