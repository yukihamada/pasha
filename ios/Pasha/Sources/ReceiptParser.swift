import Foundation

/// Smart receipt parser that uses OCR raw lines to extract structured data.
/// Works like a lightweight "prompt" — applies Japanese receipt heuristics
/// to understand receipt structure without an LLM.
struct ReceiptParser {

    struct Result {
        var vendor: String?
        var amount: Int?
        var date: Date?
        var category: String?
        var taxAmount: Int?
        var items: [(name: String, price: Int)]
    }

    /// Parse OCR lines into structured receipt data
    static func parse(lines: [String]) -> Result {
        let cleaned = lines.map { clean($0) }.filter { !$0.isEmpty }
        var result = Result(items: [])

        result.vendor = extractVendor(cleaned)
        result.amount = extractTotalAmount(cleaned)
        result.date = extractDate(cleaned)
        result.category = guessCategory(vendor: result.vendor, items: cleaned)
        result.taxAmount = extractTax(cleaned)
        result.items = extractItems(cleaned)

        return result
    }

    // MARK: - Clean

    private static func clean(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{3000}", with: " ")  // full-width space
            .replacingOccurrences(of: "　", with: " ")
    }

    // MARK: - Vendor (top of receipt, before first number line)

    private static func extractVendor(_ lines: [String]) -> String? {
        // Known chain stores — match first
        let knownStores = [
            "セブンイレブン", "セブン-イレブン", "7-ELEVEN", "ファミリーマート", "ファミマ",
            "ローソン", "LAWSON", "ミニストップ", "デイリーヤマザキ",
            "スターバックス", "STARBUCKS", "ドトール", "DOUTOR", "タリーズ", "TULLY'S",
            "マクドナルド", "McDonald", "モスバーガー", "すき家", "吉野家", "松屋",
            "イオン", "AEON", "ヨドバシ", "ビックカメラ", "ヤマダ電機",
            "ユニクロ", "UNIQLO", "ダイソー", "DAISO", "無印良品", "MUJI",
            "Amazon", "楽天", "メルカリ",
            "JR", "東急", "小田急", "京王", "西武", "東武", "東京メトロ",
            "Uber", "タクシー", "TAXI",
        ]

        for line in lines {
            for store in knownStores {
                if line.localizedCaseInsensitiveContains(store) {
                    return line
                }
            }
        }

        // Store indicators
        let indicators = ["店", "支店", "本店", "株式会社", "(株)", "有限会社",
                          "マート", "ストア", "ショップ", "スーパー", "薬局", "ドラッグ",
                          "モール", "百貨店", "カフェ", "レストラン", "食堂"]

        for line in lines.prefix(5) {
            if line.count < 2 || line.count > 40 { continue }
            if isAmountLine(line) || isDateLine(line) || isNoiseLine(line) { continue }
            for ind in indicators {
                if line.contains(ind) { return line }
            }
        }

        // Fallback: first meaningful line
        for line in lines.prefix(3) {
            if line.count < 2 || line.count > 30 { continue }
            if isAmountLine(line) || isDateLine(line) || isNoiseLine(line) { continue }
            let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            if letters >= 2 { return line }
        }

        return nil
    }

    // MARK: - Amount (total/grand total)

    private static func extractTotalAmount(_ lines: [String]) -> Int? {
        // Priority keywords — most specific first
        let keywords = [
            "合計(税込)", "税込合計", "合計金額", "総合計", "お会計",
            "お支払合計", "お支払い金額", "お支払い合計", "請求金額", "ご請求額",
            "合計", "お支払", "お買上", "お買い上げ", "小計",
            "TOTAL", "Total", "total"
        ]

        // Pass 1: keyword + number on same line
        for keyword in keywords {
            for (i, line) in lines.enumerated() {
                let norm = line.replacingOccurrences(of: " ", with: "")
                if norm.contains(keyword) {
                    if let num = extractNumber(from: line) { return num }
                    // Check next line
                    if i + 1 < lines.count {
                        if let num = extractNumber(from: lines[i + 1]) { return num }
                    }
                }
            }
        }

        // Pass 2: lines with ¥ symbol — pick the largest
        var yenAmounts: [Int] = []
        for line in lines {
            if line.contains("¥") || line.contains("￥") || line.contains("円") {
                if let num = extractNumber(from: line), num >= 10 {
                    yenAmounts.append(num)
                }
            }
        }
        if let largest = yenAmounts.max() { return largest }

        // Pass 3: largest number overall (likely total)
        var allNums: [Int] = []
        for line in lines {
            if let num = extractNumber(from: line), num >= 10 {
                allNums.append(num)
            }
        }
        return allNums.max()
    }

    // MARK: - Date

    private static func extractDate(_ lines: [String]) -> Date? {
        for line in lines {
            if let date = parseDate(from: line) { return date }
        }
        return nil
    }

    private static func parseDate(from text: String) -> Date? {
        let patterns: [(String, (NSTextCheckingResult) -> Date?)] = [
            // 2026/03/18, 2026-03-18, 2026.03.18
            ("(20\\d{2})[/\\-\\.](\\d{1,2})[/\\-\\.](\\d{1,2})", { m in
                ymd(m, text, adj: false)
            }),
            // 2026年3月18日
            ("(20\\d{2})年\\s?(\\d{1,2})月\\s?(\\d{1,2})日", { m in
                ymd(m, text, adj: false)
            }),
            // 令和8年3月18日, R8.3.18
            ("(?:令和|R)\\s?(\\d{1,2})[年\\./](\\d{1,2})[月\\./](\\d{1,2})", { m in
                guard let r = range(m, 1, text), let mo = range(m, 2, text), let d = range(m, 3, text),
                      let reiwa = Int(r), let month = Int(mo), let day = Int(d) else { return nil }
                return makeDate(reiwa + 2018, month, day)
            }),
            // 26/03/18 (2-digit year)
            ("(\\d{2})[/\\-\\.](\\d{1,2})[/\\-\\.](\\d{1,2})", { m in
                ymd(m, text, adj: true)
            }),
        ]

        for (pattern, handler) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let date = handler(match) else { continue }
            return date
        }
        return nil
    }

    // MARK: - Tax

    private static func extractTax(_ lines: [String]) -> Int? {
        let taxKeywords = ["消費税", "内税", "税額", "税", "10%対象", "8%対象"]
        for keyword in taxKeywords {
            for line in lines {
                if line.contains(keyword) {
                    if let num = extractNumber(from: line), num > 0 { return num }
                }
            }
        }
        return nil
    }

    // MARK: - Items

    private static func extractItems(_ lines: [String]) -> [(name: String, price: Int)] {
        var items: [(String, Int)] = []
        let skipWords = ["合計", "小計", "消費税", "お支払", "お釣", "預", "お買上",
                         "クレジット", "現金", "VISA", "Master", "Suica", "PayPay"]

        for line in lines {
            if skipWords.contains(where: { line.contains($0) }) { continue }
            if isNoiseLine(line) || isDateLine(line) { continue }

            // Look for pattern: item name + price (e.g. "コーヒー ¥480" or "コーヒー 480")
            if let num = extractNumber(from: line), num > 0, num < 1_000_000 {
                let namePart = line
                    .replacingOccurrences(of: "[¥￥\\d,\\.円]+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "[×x\\*]\\d+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if namePart.count >= 2 {
                    items.append((namePart, num))
                }
            }
        }
        return items
    }

    // MARK: - Category Guess

    private static func guessCategory(vendor: String?, items: [String]) -> String? {
        let all = (vendor ?? "") + " " + items.joined(separator: " ")
        let lower = all.lowercased()

        let rules: [(String, [String])] = [
            ("交通費", ["JR", "電車", "バス", "タクシー", "TAXI", "Uber", "駅", "乗車", "定期", "Suica", "PASMO", "東急", "小田急", "京王", "メトロ"]),
            ("食費", ["ランチ", "ディナー", "弁当", "おにぎり", "サンドイッチ", "パン", "惣菜", "食品", "スーパー", "イオン", "コンビニ", "セブン", "ローソン", "ファミマ"]),
            ("交際費", ["カフェ", "コーヒー", "スターバックス", "ドトール", "タリーズ", "居酒屋", "レストラン", "飲食", "懇親"]),
            ("消耗品費", ["ヨドバシ", "ビックカメラ", "ヤマダ", "Amazon", "楽天", "USB", "ケーブル", "文具", "コピー", "トナー", "ダイソー"]),
            ("通信費", ["携帯", "スマホ", "au", "docomo", "SoftBank", "Wi-Fi", "プロバイダ", "回線"]),
            ("旅費", ["ホテル", "旅館", "航空", "ANA", "JAL", "新幹線", "宿泊"]),
        ]

        for (category, keywords) in rules {
            for kw in keywords {
                if lower.localizedCaseInsensitiveContains(kw) { return category }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func extractNumber(from text: String) -> Int? {
        // Match numbers with optional ¥/￥ prefix and comma separators
        let pattern = try! NSRegularExpression(pattern: "[¥￥]?\\s?([\\d,]+)(?:\\.\\d+)?\\s?(?:円)?")
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)

        var best: Int?
        for match in matches {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let str = text[r].replacingOccurrences(of: ",", with: "")
            guard let num = Int(str), num > 0 else { continue }
            if best == nil || num > best! { best = num }
        }
        return best
    }

    private static func isAmountLine(_ line: String) -> Bool {
        line.allSatisfy { "0123456789¥￥,. 円".contains($0) }
    }

    private static func isDateLine(_ line: String) -> Bool {
        let datePattern = try! NSRegularExpression(pattern: "(20)?\\d{2}[/\\-\\.]\\d{1,2}[/\\-\\.]\\d{1,2}")
        return datePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        if line.count < 2 { return true }
        if line.allSatisfy({ "-=*#: \t".contains($0) }) { return true }
        let noiseStarts = ["TEL", "tel", "電話", "T\u{200B}", "登録番号", "No.", "#", "領収", "レシート"]
        return noiseStarts.contains(where: { line.hasPrefix($0) })
    }

    private static func ymd(_ m: NSTextCheckingResult, _ text: String, adj: Bool) -> Date? {
        guard let y = range(m, 1, text), let mo = range(m, 2, text), let d = range(m, 3, text),
              var year = Int(y), let month = Int(mo), let day = Int(d) else { return nil }
        if adj && year < 100 { year += 2000 }
        return makeDate(year, month, day)
    }

    private static func range(_ m: NSTextCheckingResult, _ i: Int, _ text: String) -> String? {
        guard let r = Range(m.range(at: i), in: text) else { return nil }
        return String(text[r])
    }

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        guard year >= 2000, year <= 2100, month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }
}
