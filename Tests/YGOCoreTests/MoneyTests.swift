import Testing
@testable import YGOCore

@Suite("Money")
struct MoneyTests {
    /// Evidence for NFR2: the arithmetic is exact, which floating point is not.
    @Test func summingTenThousandPricesIsExact() {
        let price = Money(amount: 0.89, currency: .eur)
        #expect(price.cents == 89)

        let total = Array(repeating: price, count: 10_000).total(in: .eur)
        #expect(total?.cents == 890_000)
        #expect(total?.amount == 8_900.0)
        #expect(total?.formatted == "€8900.00")

        // The same sum in floating point does not land on the exact figure.
        var drifting = 0.0
        for _ in 0..<10_000 { drifting += 0.89 }
        #expect(drifting != 8_900.0, "il float deriva, ed è il motivo dei centesimi interi")
        #expect(abs(drifting - 8_900.0) > 0)

        // Multiplication is exact too.
        #expect(price.times(10_000).cents == 890_000)
        #expect(price.times(0).cents == 0)
        #expect(price.times(-5).cents == 0, "una quantità negativa non vale meno di zero")
    }

    /// Evidence for NFR2: a total in no currency is worse than no total.
    @Test func refusesToAddAcrossCurrencies() {
        let euros = Money(amount: 10, currency: .eur)
        let dollars = Money(amount: 10, currency: .usd)

        #expect(euros.adding(dollars) == nil)
        #expect(dollars.adding(euros) == nil)
        #expect(euros.subtracting(dollars) == nil)
        #expect([euros, dollars].total(in: .eur) == nil)
        #expect([euros, dollars].total(in: .usd) == nil)

        // Within one currency it adds as expected.
        #expect(euros.adding(euros)?.cents == 2_000)
        #expect([euros, euros, euros].total(in: .eur)?.amount == 30)
        #expect(euros.subtracting(Money(amount: 3, currency: .eur))?.amount == 7)

        // And an empty sum is zero in the currency asked for.
        #expect([Money]().total(in: .eur) == Money.zero(.eur))
    }

    /// Two of the five sources publish a different kind of number, and the
    /// type says so.
    @Test func namesTheTwoSourcesThatCarryAskingPrices() {
        let asking = PriceSource.allCases.filter(\.carriesAskingPrices)
        #expect(Set(asking) == [.ebay, .amazon])

        let market = PriceSource.allCases.filter { !$0.carriesAskingPrices }
        #expect(Set(market) == [.cardmarket, .tcgplayer, .coolstuffinc])

        // Cardmarket is the default, and it is European.
        #expect(PriceSource.default == .cardmarket)
        #expect(PriceSource.cardmarket.currency == .eur)
        #expect(PriceSource.tcgplayer.currency == .usd)
        #expect(PriceSource.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    /// Rounding happens once, on the way in.
    @Test func roundsToTheNearestCentOnce() {
        #expect(Money(amount: 0.005, currency: .eur).cents == 1)
        #expect(Money(amount: 0.004, currency: .eur).cents == 0)
        #expect(Money(amount: 999.99, currency: .eur).cents == 99_999)
        #expect(Money(amount: 0.02, currency: .eur).cents == 2)

        // And a round trip through Double does not drift.
        for cents in [1, 2, 89, 999, 99_999] {
            #expect(Money(amount: Money(cents: cents, currency: .eur).amount,
                          currency: .eur).cents == cents)
        }
    }
}
