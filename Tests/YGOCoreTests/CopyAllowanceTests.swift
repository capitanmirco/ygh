import Testing
@testable import YGOCore

@Suite("Copy allowance")
struct CopyAllowanceTests {
    /// Evidence for R6.AC6: the four ban statuses map to zero, one, two and
    /// three permitted copies.
    @Test func mapsEachBanStatusToItsCopyAllowance() {
        #expect(BanStatus.forbidden.copyAllowance.maximumCopies == 0)
        #expect(BanStatus.limited.copyAllowance.maximumCopies == 1)
        #expect(BanStatus.semiLimited.copyAllowance.maximumCopies == 2)
        #expect(BanStatus.unlimited.copyAllowance.maximumCopies == 3)

        // Every case is covered, so a new status cannot silently default.
        #expect(BanStatus.allCases.count == 4)
    }

    @Test func permitsCountsUpToTheAllowanceAndNoMore() {
        #expect(BanStatus.limited.copyAllowance.permits(1))
        #expect(!BanStatus.limited.copyAllowance.permits(2))
        #expect(BanStatus.forbidden.copyAllowance.permits(0))
        #expect(!BanStatus.forbidden.copyAllowance.permits(1))
    }

    /// `unlimited` is expressed by the absence of a stored row, so it must not
    /// round-trip to a storable value.
    @Test func onlyRestrictingStatusesHaveAStoredForm() {
        #expect(BanStatus.unlimited.storedValue == nil)
        #expect(BanStatus.forbidden.storedValue == "forbidden")
        #expect(BanStatus.limited.storedValue == "limited")
        #expect(BanStatus.semiLimited.storedValue == "semi_limited")

        for status in BanStatus.allCases {
            #expect(BanStatus(storedValue: status.storedValue) == status)
        }
    }

    @Test func onlyTcgOcgAndGoatCarryUpstreamBanLists() {
        let withUpstream = CardFormat.allCases.filter(\.hasUpstreamBanList)
        #expect(Set(withUpstream) == [.tcg, .ocg, .goat])
    }
}
