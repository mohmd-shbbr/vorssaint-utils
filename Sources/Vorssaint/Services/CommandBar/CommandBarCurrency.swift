// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Explicit currency queries only. Amounts never leave the Mac.
enum CommandBarCurrency {
    struct Query: Equatable {
        let amount: Double
        let base: String
        let quote: String
        var pair: String { base + "/" + quote }
    }
    private static let aliases: [String: String] = [
        "$": "USD", "us$": "USD", "dollar": "USD", "dollars": "USD",
        "€": "EUR", "euro": "EUR", "euros": "EUR",
        "₹": "INR", "rs": "INR", "rupee": "INR", "rupees": "INR",
        "£": "GBP", "pound": "GBP", "pounds": "GBP", "sterling": "GBP",
        "yen": "JPY", "yuan": "CNY", "dirham": "AED", "dirhams": "AED",
        "franc": "CHF", "francs": "CHF", "a$": "AUD", "c$": "CAD",
        "s$": "SGD", "hk$": "HKD", "nz$": "NZD"
    ]
    static func code(_ token: String) -> String? {
        let key = token.lowercased().trimmingCharacters(in: .whitespaces)
        if let alias = aliases[key] { return alias }
        let upper = key.uppercased()
        return Locale.commonISOCurrencyCodes.contains(upper) ? upper : nil
    }
    static func parse(_ text: String) -> Query? {
        let pattern = #"^\s*(?:(?<prefix>US\$|HK\$|NZ\$|A\$|C\$|S\$|[$€₹£])\s*)?(?<amount>[+-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?)\s*(?<source>[A-Za-z$€₹£]+)?(?:\s+(?:(?:to|in|into)\s+|(?:→|->)\s*)(?<target>[A-Za-z$€₹£]+))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ name: String) -> String {
            guard let range = Range(match.range(withName: name), in: text) else { return "" }
            return String(text[range])
        }
        let prefix = group("prefix"), source = group("source")
        guard prefix.isEmpty || source.isEmpty,
              let base = code(prefix.isEmpty ? source : prefix), let quote = code(group("target").isEmpty ? "INR" : group("target")),
              let amount = Double(group("amount").replacingOccurrences(of: ",", with: "")), amount.isFinite else { return nil }
        return Query(amount: amount, base: base, quote: quote)
    }
    static func format(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.currencySymbol = currency + " "
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(amount)"
    }
}

/// Main-thread state, asynchronous requests, one request per pair per hour.
/// Successful observations persist across launches; failures retain cached rates.
final class CommandBarCurrencyRates {
    static let shared = CommandBarCurrencyRates()
    struct Rate: Codable {
        let date: String
        let base: String
        let quote: String
        let rate: Double
    }
    struct Cached: Codable { let observation: Rate; let fetched: Date }
    struct Answer { let title: String; let detail: String; let copyable: Bool }
    var onResult: (() -> Void)?
    private let key = "commandBar.currencyRates.v1"
    private var cache: [String: Cached] = [:]
    private var pending: Set<String> = []
    private var failures: [String: Date] = [:]
    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: Cached].self, from: data) { cache = saved }
    }
    func answer(for text: String) -> Answer? {
        guard let query = CommandBarCurrency.parse(text) else { return nil }
        if query.base == query.quote {
            return Answer(title: CommandBarCurrency.format(query.amount, currency: query.quote), detail: "Same currency", copyable: true)
        }
        let saved = cache[query.pair]
        let fresh = saved.map { Date().timeIntervalSince($0.fetched) < 3600 } ?? false
        let recentlyFailed = failures[query.pair].map { Date().timeIntervalSince($0) < 60 } ?? false
        if !fresh && !recentlyFailed && !pending.contains(query.pair) { fetch(query) }
        if let saved {
            let value = query.amount * saved.observation.rate
            guard value.isFinite else { return Answer(title: "Amount is too large", detail: "Try a smaller amount", copyable: false) }
            return Answer(title: CommandBarCurrency.format(value, currency: query.quote),
                          detail: "Frankfurter · \(saved.observation.date) · Daily rate" + (fresh ? "" : " · Cached"), copyable: true)
        }
        return Answer(title: recentlyFailed ? "Exchange rate unavailable" : "Fetching exchange rate…",
                      detail: recentlyFailed ? "Check your connection or try again shortly" : "\(query.base) → \(query.quote) · Frankfurter daily rates", copyable: false)
    }
    private func fetch(_ query: CommandBarCurrency.Query) {
        pending.insert(query.pair)
        let url = URL(string: "https://api.frankfurter.dev/v2/rate/\(query.base.lowercased())/\(query.quote.lowercased())")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let decoded = data.flatMap { try? JSONDecoder().decode(Rate.self, from: $0) }
            let valid = (response as? HTTPURLResponse)?.statusCode == 200 && decoded?.base == query.base
                && decoded?.quote == query.quote && (decoded?.rate ?? 0) > 0 && (decoded?.rate.isFinite ?? false)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending.remove(query.pair)
                if valid, let decoded {
                    self.cache[query.pair] = Cached(observation: decoded, fetched: Date())
                    self.failures.removeValue(forKey: query.pair)
                    if let data = try? JSONEncoder().encode(self.cache) { UserDefaults.standard.set(data, forKey: self.key) }
                } else { self.failures[query.pair] = Date() }
                self.onResult?()
            }
        }.resume()
    }
}
