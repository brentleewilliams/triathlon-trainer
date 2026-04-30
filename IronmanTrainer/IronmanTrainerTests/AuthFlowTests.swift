import XCTest
@testable import Race1_Trainer

// MARK: - AuthPlanCache Unit Tests
//
// These tests cover the UserDefaults plan cache logic that drives the
// "skip onboarding / show onboarding" decision. No Firebase instance needed.
//
// Manual device tests required for Firebase-dependent paths are documented
// at the bottom of this file.

final class AuthPlanCacheTests: XCTestCase {

    // Isolated UserDefaults suite — never touches UserDefaults.standard.
    var defaults: UserDefaults!
    let uid1 = "uid-email-abc123"
    let uid2 = "uid-apple-xyz789"
    let aliasUID = "uid-email-alias-456"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.race1.tests.authcache")!
        defaults.removePersistentDomain(forName: "com.race1.tests.authcache")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "com.race1.tests.authcache")
        defaults = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makePlan(weeks: Int = 2) -> [TrainingWeek] {
        (1...weeks).map { w in
            TrainingWeek(
                weekNumber: w,
                phase: "Base",
                startDate: Date(),
                endDate: Date().addingTimeInterval(Double(w) * 604800),
                workouts: []
            )
        }
    }

    // MARK: - Cache Miss (new user)

    func testCacheMiss_newUID_returnsNil() {
        XCTAssertNil(AuthPlanCache.read(uid: uid1, defaults: defaults))
    }

    func testCacheMiss_noFlag_returnsNil() {
        // Plan data present but flag missing — should still miss.
        let plan = makePlan()
        AuthPlanCache.write(uid: uid1, plan: plan, defaults: defaults)
        XCTAssertNil(AuthPlanCache.read(uid: uid1, defaults: defaults))
    }

    func testCacheMiss_flagSetButNoPlanData_returnsNil() {
        // Flag set but no encoded plan — corrupt cache scenario.
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)
        XCTAssertNil(AuthPlanCache.read(uid: uid1, defaults: defaults))
    }

    func testFlagExists_falseForNewUID() {
        XCTAssertFalse(AuthPlanCache.flagExists(uid: uid1, defaults: defaults))
    }

    // MARK: - Cache Hit (returning user)

    func testCacheHit_returnsStoredPlan() {
        let plan = makePlan(weeks: 3)
        AuthPlanCache.write(uid: uid1, plan: plan, defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)

        let loaded = AuthPlanCache.read(uid: uid1, defaults: defaults)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 3)
        XCTAssertEqual(loaded?.first?.weekNumber, 1)
        XCTAssertEqual(loaded?.last?.weekNumber, 3)
    }

    func testCacheHit_flagExists() {
        AuthPlanCache.write(uid: uid1, plan: makePlan(), defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)
        XCTAssertTrue(AuthPlanCache.flagExists(uid: uid1, defaults: defaults))
    }

    // MARK: - UID Isolation (the core auth correctness invariant)
    //
    // Different sign-in methods (email OTP vs Apple) create different Firebase
    // UIDs. Each UID must have completely separate cache entries — a plan for
    // uid1 must never surface for uid2.

    func testUIDIsolation_uid1CacheDoesNotAffectUID2() {
        let plan = makePlan(weeks: 4)
        AuthPlanCache.write(uid: uid1, plan: plan, defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)

        XCTAssertNil(AuthPlanCache.read(uid: uid2, defaults: defaults))
        XCTAssertFalse(AuthPlanCache.flagExists(uid: uid2, defaults: defaults))
    }

    func testUIDIsolation_bothUIDs_independentPlans() {
        let plan1 = makePlan(weeks: 2)
        let plan2 = makePlan(weeks: 5)

        AuthPlanCache.write(uid: uid1, plan: plan1, defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)
        AuthPlanCache.write(uid: uid2, plan: plan2, defaults: defaults)
        AuthPlanCache.setFlag(uid: uid2, defaults: defaults)

        XCTAssertEqual(AuthPlanCache.read(uid: uid1, defaults: defaults)?.count, 2)
        XCTAssertEqual(AuthPlanCache.read(uid: uid2, defaults: defaults)?.count, 5)
    }

    func testUIDIsolation_aliasedEmailUID_separateFromRealEmailUID() {
        // brentleewilliams+test@gmail.com creates a different Firebase UID
        // than brentleewilliams@gmail.com — verify cache keys are isolated.
        let plan = makePlan(weeks: 2)
        AuthPlanCache.write(uid: uid1, plan: plan, defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)

        XCTAssertNil(AuthPlanCache.read(uid: aliasUID, defaults: defaults))
        XCTAssertFalse(AuthPlanCache.flagExists(uid: aliasUID, defaults: defaults))
    }

    // MARK: - Cache Clear

    func testCacheClear_removesDataAndFlag() {
        AuthPlanCache.write(uid: uid1, plan: makePlan(), defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)
        AuthPlanCache.clear(uid: uid1, defaults: defaults)

        XCTAssertNil(AuthPlanCache.read(uid: uid1, defaults: defaults))
        XCTAssertFalse(AuthPlanCache.flagExists(uid: uid1, defaults: defaults))
    }

    func testCacheClear_onlyAffectsTargetUID() {
        AuthPlanCache.write(uid: uid1, plan: makePlan(weeks: 2), defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)
        AuthPlanCache.write(uid: uid2, plan: makePlan(weeks: 3), defaults: defaults)
        AuthPlanCache.setFlag(uid: uid2, defaults: defaults)

        AuthPlanCache.clear(uid: uid1, defaults: defaults)

        XCTAssertNil(AuthPlanCache.read(uid: uid1, defaults: defaults))
        XCTAssertEqual(AuthPlanCache.read(uid: uid2, defaults: defaults)?.count, 3)
    }

    // MARK: - Key Format

    func testFlagKey_includesUID() {
        XCTAssertEqual(AuthPlanCache.flagKey(uid1), "onboarding_complete_\(uid1)")
    }

    func testPlanKey_includesUID() {
        XCTAssertEqual(AuthPlanCache.planKey(uid1), "saved_plan_\(uid1)")
    }

    func testFlagKeys_differentForDifferentUIDs() {
        XCTAssertNotEqual(AuthPlanCache.flagKey(uid1), AuthPlanCache.flagKey(uid2))
    }

    // MARK: - Round-trip Encoding

    func testRoundTrip_planDataSurvivesEncodeDecycle() throws {
        let original = makePlan(weeks: 17)
        AuthPlanCache.write(uid: uid1, plan: original, defaults: defaults)
        AuthPlanCache.setFlag(uid: uid1, defaults: defaults)

        let loaded = try XCTUnwrap(AuthPlanCache.read(uid: uid1, defaults: defaults))
        XCTAssertEqual(loaded.count, original.count)
        for (a, b) in zip(original, loaded) {
            XCTAssertEqual(a.weekNumber, b.weekNumber)
            XCTAssertEqual(a.phase, b.phase)
        }
    }
}

// MARK: - MockAuthService State Machine Tests
//
// Tests the sign-out state clearing logic without a live Firebase dependency.
// MockAuthService mirrors AuthService's published properties and sign-out logic.

@MainActor
final class AuthSignOutStateTests: XCTestCase {

    // Mirrors the state cleared by AuthService.signOut().
    class MockAuthService {
        var isAuthenticated = false
        var currentUserID: String?
        var currentUserEmail: String?
        var onboardingComplete = false
        var savedPlan: [TrainingWeek]?

        func loadSession(uid: String, email: String, plan: [TrainingWeek]) {
            isAuthenticated = true
            currentUserID = uid
            currentUserEmail = email
            onboardingComplete = true
            savedPlan = plan
        }

        func signOut() {
            isAuthenticated = false
            currentUserID = nil
            currentUserEmail = nil
            onboardingComplete = false
            savedPlan = nil
        }
    }

    var auth: MockAuthService!

    override func setUp() {
        super.setUp()
        auth = MockAuthService()
    }

    // MARK: - Sign-out clears all state

    func testSignOut_clearsIsAuthenticated() {
        auth.loadSession(uid: "u1", email: "a@b.com", plan: [])
        auth.signOut()
        XCTAssertFalse(auth.isAuthenticated)
    }

    func testSignOut_clearsCurrentUserID() {
        auth.loadSession(uid: "u1", email: "a@b.com", plan: [])
        auth.signOut()
        XCTAssertNil(auth.currentUserID)
    }

    func testSignOut_clearsCurrentUserEmail() {
        auth.loadSession(uid: "u1", email: "a@b.com", plan: [])
        auth.signOut()
        XCTAssertNil(auth.currentUserEmail)
    }

    func testSignOut_clearsOnboardingComplete() {
        auth.loadSession(uid: "u1", email: "a@b.com", plan: [])
        auth.signOut()
        XCTAssertFalse(auth.onboardingComplete)
    }

    func testSignOut_clearsSavedPlan() {
        let plan = (1...3).map { TrainingWeek(weekNumber: $0, phase: "Base", startDate: Date(), endDate: Date(), workouts: []) }
        auth.loadSession(uid: "u1", email: "a@b.com", plan: plan)
        auth.signOut()
        XCTAssertNil(auth.savedPlan)
    }

    // MARK: - Sign-out then sign-in as different user

    func testSignOut_thenNewUser_startsClean() {
        auth.loadSession(uid: "uid-email", email: "user@example.com", plan: [])
        auth.signOut()

        // Simulate new Apple Sign In — new UID, onboardingComplete must start false
        auth.isAuthenticated = true
        auth.currentUserID = "uid-apple-new"
        auth.currentUserEmail = "relay@privaterelay.appleid.com"
        // onboardingComplete stays false until checkForExistingPlan finds a plan
        XCTAssertFalse(auth.onboardingComplete)
        XCTAssertNil(auth.savedPlan)
    }

    func testSignOut_previousPlanNotLeakedToNewUser() {
        let plan = (1...5).map { TrainingWeek(weekNumber: $0, phase: "Base", startDate: Date(), endDate: Date(), workouts: []) }
        auth.loadSession(uid: "uid-old", email: "old@example.com", plan: plan)
        XCTAssertNotNil(auth.savedPlan)

        auth.signOut()

        // New user signs in
        auth.isAuthenticated = true
        auth.currentUserID = "uid-new"
        XCTAssertNil(auth.savedPlan, "Previous user's plan must not be visible to new user")
    }

    // MARK: - Fast sign-out / sign-in race condition

    func testRaceCondition_immediateReSignIn_onboardingNotInherited() {
        // Simulates: sign out + immediately sign in before auth listener fires nil.
        // signOut() must clear state synchronously so the new session starts clean.
        auth.loadSession(uid: "uid-email", email: "user@example.com", plan: [])

        // Sign out resets state synchronously
        auth.signOut()

        // New sign-in happens before nil-user listener fires
        auth.isAuthenticated = true
        auth.currentUserID = "uid-apple"

        // onboardingComplete is still false — was cleared by signOut()
        XCTAssertFalse(auth.onboardingComplete)
    }
}

// MARK: - Sign-Out UserDefaults Wipe Tests
//
// These are the tests that would have caught the race-data-leak bug.
// They drive AuthService.wipeLocalDefaults() directly with an isolated
// UserDefaults suite so no Firebase dependency is needed.

final class SignOutWipeTests: XCTestCase {

    let suite = "com.race1.tests.signoutwipe"
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    // MARK: - The actual bug: global race keys must not survive sign-out

    func testWipe_clearsRaceDate() {
        defaults.set(Date().timeIntervalSince1970, forKey: "race_date")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)
        XCTAssertEqual(defaults.double(forKey: "race_date"), 0,
                       "race_date left over from user A was visible to user B")
    }

    func testWipe_clearsRacePrimaryName() {
        defaults.set("Chicago Marathon", forKey: "race_primary_name")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)
        XCTAssertNil(defaults.string(forKey: "race_primary_name"),
                     "race_primary_name from user A leaked to user B")
    }

    func testWipe_clearsRacePrimaryVenue() {
        defaults.set("Chicago, IL", forKey: "race_primary_venue")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)
        XCTAssertNil(defaults.string(forKey: "race_primary_venue"))
    }

    func testWipe_clearsChatHistory() {
        defaults.set(Data(), forKey: "coaching_chat_history")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)
        XCTAssertNil(defaults.data(forKey: "coaching_chat_history"),
                     "chat history from user A leaked to user B")
    }

    func testWipe_clearsRaceSports() {
        defaults.set(["swim", "bike", "run"], forKey: "race_sports")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)
        XCTAssertNil(defaults.array(forKey: "race_sports"))
    }

    func testWipe_clearsOnboardingDate() {
        defaults.set(Date().timeIntervalSince1970, forKey: "onboarding_date_global")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)
        XCTAssertEqual(defaults.double(forKey: "onboarding_date_global"), 0)
    }

    func testWipe_preservesHasLaunchedBefore() {
        // has_launched_before must survive the wipe so the fresh-install
        // Keychain clear doesn't re-trigger on the next sign-in.
        defaults.set(true, forKey: "has_launched_before")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)
        XCTAssertTrue(defaults.bool(forKey: "has_launched_before"),
                      "has_launched_before was lost — would trigger spurious Keychain clear")
    }

    // MARK: - Cross-account isolation (the exact failure scenario)

    func testCrossAccount_userA_raceNotVisibleToUserB() {
        // User A logs in, onboards with Chicago Marathon.
        defaults.set(1_800_000_000.0, forKey: "race_date")
        defaults.set("Chicago Marathon", forKey: "race_primary_name")
        defaults.set("Chicago, IL", forKey: "race_primary_venue")
        defaults.set(["run"], forKey: "race_sports")

        // User A signs out — full wipe.
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)

        // User B signs in — must see a blank slate, not Chicago.
        XCTAssertEqual(defaults.double(forKey: "race_date"), 0)
        XCTAssertNil(defaults.string(forKey: "race_primary_name"))
        XCTAssertNil(defaults.string(forKey: "race_primary_venue"))
        XCTAssertNil(defaults.array(forKey: "race_sports"))
    }

    func testCrossAccount_userB_changesRace_notVisibleToUserA() {
        // User A has Chicago; signs out.
        defaults.set(1_800_000_000.0, forKey: "race_date")
        defaults.set("Chicago Marathon", forKey: "race_primary_name")
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)

        // User B signs in, changes race to Berlin.
        defaults.set(1_854_000_000.0, forKey: "race_date")
        defaults.set("Berlin Marathon", forKey: "race_primary_name")

        // User B signs out.
        AuthService.wipeLocalDefaults(defaults: defaults, bundleID: suite)

        // User A signs back in — must NOT see Berlin.
        XCTAssertEqual(defaults.double(forKey: "race_date"), 0,
                       "User B's Berlin race date leaked back to user A")
        XCTAssertNil(defaults.string(forKey: "race_primary_name"),
                     "User B's race name leaked back to user A")
    }
}

// MARK: - Fresh Install Detection Tests

final class FreshInstallTests: XCTestCase {

    let testSuite = "com.race1.tests.freshinstall"
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: testSuite)!
        defaults.removePersistentDomain(forName: testSuite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: testSuite)
        defaults = nil
        super.tearDown()
    }

    func testFreshInstall_hasLaunchedKey_falseByDefault() {
        XCTAssertFalse(defaults.bool(forKey: "has_launched_before"))
    }

    func testFreshInstall_hasLaunchedKey_trueAfterFirstLaunch() {
        defaults.set(true, forKey: "has_launched_before")
        XCTAssertTrue(defaults.bool(forKey: "has_launched_before"))
    }

    func testFreshInstall_reinstallSimulation_keyIsGone() {
        // Simulate install: set the key
        defaults.set(true, forKey: "has_launched_before")
        XCTAssertTrue(defaults.bool(forKey: "has_launched_before"))

        // Simulate uninstall: UserDefaults domain wiped
        defaults.removePersistentDomain(forName: testSuite)

        // Reinstall — key is gone, fresh install detected
        XCTAssertFalse(defaults.bool(forKey: "has_launched_before"))
    }

    func testFreshInstall_planCacheAlsoGone_afterReinstall() {
        // Both the plan cache and the launch flag use UserDefaults, so both
        // disappear on uninstall. Keychain (Firebase tokens) is the only thing
        // that survives — which is why clearKeychain() is called on fresh install.
        let uid = "uid-test-123"
        AuthPlanCache.write(uid: uid, plan: [], defaults: defaults)
        AuthPlanCache.setFlag(uid: uid, defaults: defaults)

        defaults.removePersistentDomain(forName: testSuite)

        XCTAssertFalse(AuthPlanCache.flagExists(uid: uid, defaults: defaults))
        XCTAssertNil(AuthPlanCache.read(uid: uid, defaults: defaults))
    }
}

/*
 ┌─────────────────────────────────────────────────────────────────────┐
 │  MANUAL DEVICE TEST MATRIX                                          │
 │  Run on a real device after each auth-related change.               │
 │  Apple Sign In removed — Email OTP is the only sign-in method.     │
 ├─────────────────────────────────────────────────────────────────────┤
 │ PATH                                          │ EXPECTED            │
 ├───────────────────────────────────────────────┼─────────────────────┤
 │ New user → Email OTP                          │ Onboarding shown    │
 │ Returning user → same email                   │ Skip, existing plan │
 │ Alias email (+tag) → new sign-in              │ Onboarding, new acct│
 │ Sign out → sign in same email (race test)     │ No session bleed    │
 │ Sign out → sign in different email            │ No session bleed    │
 │ Uninstall → reinstall → sign in               │ Onboarding shown    │
 └───────────────────────────────────────────────┴─────────────────────┘

 To reset between manual tests: uninstall the app before reinstalling.
*/
