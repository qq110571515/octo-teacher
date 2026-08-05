import XCTest
@testable import OctoTeacher

final class FamilyNetworkTests: XCTestCase {
    func testFreshStoreMigratesIntoThreeRoleFamilyNetwork() throws {
        let store = LocalFamilyStore()

        XCTAssertTrue(store.canManageFamilyMembership)
        XCTAssertEqual(store.familyNetwork.activeMembers(role: .guardian).count, 1)
        XCTAssertEqual(store.familyNetwork.activeMembers(role: .child).count, 1)
        XCTAssertEqual(store.familyNetwork.activeMembers(role: .relative).count, 0, "旧演示亲友不能自动变成真实家庭身份")
        XCTAssertEqual(store.currentFamilyMember?.role, .guardian)
        XCTAssertEqual(store.familyNetwork.devices.first?.status, .active)
    }

    func testChildProfileChangesStayAlignedWithFamilyNetwork() throws {
        let store = LocalFamilyStore()
        let child = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))

        XCTAssertEqual(store.familyNetwork.activeMembers(role: .child).count, 2)
        XCTAssertEqual(store.familyNetwork.members.first(where: { $0.childId == child.id })?.displayName, "妹妹")

        XCTAssertTrue(store.updateChildProfile(childId: child.id, name: "小月", age: 7, dailyLimitMinutes: 45))
        XCTAssertEqual(store.familyNetwork.members.first(where: { $0.childId == child.id })?.displayName, "小月")

        XCTAssertTrue(store.removeChild(child.id))
        XCTAssertNil(store.familyNetwork.members.first(where: { $0.childId == child.id }))
    }

    func testInviteRoleBoundariesAndPayloadRoundTrip() throws {
        let store = LocalFamilyStore()

        XCTAssertNil(store.issueFamilyJoinInvite(role: .child), "孩子邀请必须绑定孩子档案")
        XCTAssertNil(store.issueFamilyJoinInvite(role: .guardian, childId: store.child.id), "成人邀请不能带 childId")

        let invite = try XCTUnwrap(
            store.issueFamilyJoinInvite(
                role: .child,
                childId: store.child.id,
                suggestedDisplayName: store.child.name
            )
        )
        let payload = try XCTUnwrap(store.familyJoinPayload(for: invite))
        let encoded = try XCTUnwrap(payload.encodedValue)
        let decoded = try XCTUnwrap(FamilyJoinPayload.decode(encoded))

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.role, .child)
        XCTAssertEqual(decoded.childId, store.child.id)
        XCTAssertEqual(decoded.familyId, store.familyNetwork.familyId)
    }

    func testExpiredAndRevokedInvitesCannotProducePayload() throws {
        let store = LocalFamilyStore()
        let invite = try XCTUnwrap(store.issueFamilyJoinInvite(role: .guardian, validFor: 60))

        XCTAssertNil(store.familyJoinPayload(for: invite, at: invite.expiresAt))
        XCTAssertTrue(store.revokeFamilyJoinInvite(invite.id))
        let revoked = try XCTUnwrap(store.familyNetwork.invitations.first(where: { $0.id == invite.id }))
        XCTAssertNil(store.familyJoinPayload(for: revoked))
    }

    func testV4SnapshotWithoutNetworkMigratesAndV5RoundTrips() throws {
        let original = LocalFamilyStore()
        var legacy = original.snapshot
        legacy.schemaVersion = 4
        legacy.familyNetwork = nil
        let persistence = MemoryPersistence(snapshot: legacy)

        let migrated = LocalFamilyStore(persistence: persistence)
        XCTAssertTrue(migrated.canManageFamilyMembership)
        XCTAssertEqual(migrated.familyNetwork.activeMembers(role: .child).count, migrated.children.count)

        migrated.persist()
        let saved = try XCTUnwrap(persistence.snapshot)
        XCTAssertEqual(saved.schemaVersion, FamilyStoreSnapshot.currentSchemaVersion)
        XCTAssertNotNil(saved.familyNetwork)

        let encoder = JSONEncoder()
        let data = try encoder.encode(saved)
        let decoded = try JSONDecoder().decode(FamilyStoreSnapshot.self, from: data)
        XCTAssertEqual(decoded.familyNetwork, saved.familyNetwork)
    }

    private final class MemoryPersistence: FamilyStorePersisting {
        var snapshot: FamilyStoreSnapshot?

        init(snapshot: FamilyStoreSnapshot?) {
            self.snapshot = snapshot
        }

        func load() -> FamilyStoreSnapshot? { snapshot }
        func save(_ snapshot: FamilyStoreSnapshot) { self.snapshot = snapshot }
    }
}
