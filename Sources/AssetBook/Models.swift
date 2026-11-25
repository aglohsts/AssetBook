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
    /// 負債：每月幾號結帳、幾號繳費（或扣款）；nil 表示沒設定
    var statementDay: Int?
    var dueDay: Int?

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
        case id, name, note, category, currency, valuation, isArchived, icon, cashGroup, statementDay, dueDay
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
        statementDay = try c.decodeIfPresent(Int.self, forKey: .statementDay)
        dueDay = try c.decodeIfPresent(Int.self, forKey: .dueDay)
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

/// 負債帳戶的每月日子：結帳或繳費
struct BillEvent: Identifiable, Hashable {
    enum Kind { case statement, due }
    let account: Account
    let kind: Kind
    let date: Date
    var id: String { "\(account.id)-\(kind)-\(date.timeIntervalSince1970)" }
    /// 月曆上的短字
    var shortTitle: String { kind == .due ? "繳" : "結" }
    var title: String { kind == .due ? (account.note.contains("扣款") ? "扣款" : "繳費") : "結帳" }
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
    /// 這個帳戶在 from 當天或之後、within 天內的結帳日與繳費日
    func billEvents(from: Date, within days: Int, calendar cal: Calendar = .current) -> [BillEvent] {
        let today = cal.startOfDay(for: from)
        guard let end = cal.date(byAdding: .day, value: days, to: today) else { return [] }
        var out: [BillEvent] = []
        for (day, kind) in [(statementDay, BillEvent.Kind.statement), (dueDay, .due)] {
            guard let day else { continue }
            var month = today
            while let d = cal.date(day: day, inMonthOf: month), d <= end {
                if d >= today { out.append(BillEvent(account: self, kind: kind, date: d)) }
                guard let next = cal.date(byAdding: .month, value: 1, to: month) else { break }
                month = next
            }
        }
        return out
    }
}
