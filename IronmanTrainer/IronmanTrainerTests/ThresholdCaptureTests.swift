import XCTest
@testable import Race1_Trainer

final class ThresholdCaptureTests: XCTestCase {

    var vm: ChatViewModel!

    @MainActor
    override func setUp() {
        super.setUp()
        PerformanceThresholdsStore.clear()
        vm = ChatViewModel(skipHistory: true)
    }

    @MainActor
    override func tearDown() {
        PerformanceThresholdsStore.clear()
        vm = nil
        super.tearDown()
    }

    // MARK: - Payload parsing

    @MainActor
    func testExtractPayload_FtpWatts_SnakeCase() {
        let text = "Nice, logging that. [CAPTURE_THRESHOLD:{\"ftp_watts\": 215}]"
        let payload = vm.extractThresholdPayload(from: text)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.ftpWatts, 215)
        XCTAssertNil(payload?.thresholdPaceSecondsPerMile)
        XCTAssertNil(payload?.cssSecondsPer100yd)
    }

    @MainActor
    func testExtractPayload_AllFields() {
        let text = "[CAPTURE_THRESHOLD:{\"ftp_watts\": 220, \"threshold_pace_seconds_per_mile\": 450, \"css_seconds_per_100yd\": 95}]"
        let payload = vm.extractThresholdPayload(from: text)
        XCTAssertEqual(payload?.ftpWatts, 220)
        XCTAssertEqual(payload?.thresholdPaceSecondsPerMile, 450)
        XCTAssertEqual(payload?.cssSecondsPer100yd, 95)
    }

    @MainActor
    func testExtractPayload_ToolCallFormat() {
        let text = "Got it. [TOOL_CALL:capture_threshold:{\"threshold_pace_seconds_per_mile\": 420}]"
        let payload = vm.extractThresholdPayload(from: text)
        XCTAssertEqual(payload?.thresholdPaceSecondsPerMile, 420)
    }

    @MainActor
    func testExtractPayload_NoMarker_ReturnsNil() {
        let text = "Your threshold pace sounds great."
        XCTAssertNil(vm.extractThresholdPayload(from: text))
    }

    @MainActor
    func testExtractPayload_EmptyPayload_ReturnsNil() {
        let text = "[CAPTURE_THRESHOLD:{}]"
        XCTAssertNil(vm.extractThresholdPayload(from: text))
    }

    @MainActor
    func testExtractPayload_MalformedJSON_ReturnsNil() {
        let text = "[CAPTURE_THRESHOLD:{not json}]"
        XCTAssertNil(vm.extractThresholdPayload(from: text))
    }

    // MARK: - Persistence

    @MainActor
    func testApplyThresholdCapture_PersistsToStore() {
        let text = "OK — [CAPTURE_THRESHOLD:{\"ftp_watts\": 215}]"
        let result = vm.applyThresholdCaptureIfPresent(in: text)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ftpWatts, 215)

        let loaded = PerformanceThresholdsStore.load()
        XCTAssertEqual(loaded?.ftpWatts, 215)
        XCTAssertEqual(loaded?.source, .userEntered)
        XCTAssertNotNil(loaded?.capturedAt)
    }

    @MainActor
    func testApplyThresholdCapture_MergesWithExisting() {
        // First capture: FTP only.
        _ = vm.applyThresholdCaptureIfPresent(in: "[CAPTURE_THRESHOLD:{\"ftp_watts\": 200}]")
        // Second capture: run pace only. FTP must survive.
        _ = vm.applyThresholdCaptureIfPresent(in: "[CAPTURE_THRESHOLD:{\"threshold_pace_seconds_per_mile\": 450}]")

        let loaded = PerformanceThresholdsStore.load()
        XCTAssertEqual(loaded?.ftpWatts, 200, "Earlier capture should persist after merge")
        XCTAssertEqual(loaded?.thresholdPaceSecondsPerMile, 450)
    }

    @MainActor
    func testApplyThresholdCapture_NoPayload_NoSideEffects() {
        let result = vm.applyThresholdCaptureIfPresent(in: "Just a normal coaching response.")
        XCTAssertNil(result)
        XCTAssertNil(PerformanceThresholdsStore.load())
    }

    // MARK: - Store merge helper directly

    func testStoreMerge_StartsEmpty() {
        XCTAssertNil(PerformanceThresholdsStore.load())
        let merged = PerformanceThresholdsStore.merge(ftpWatts: 210)
        XCTAssertEqual(merged.ftpWatts, 210)
        XCTAssertEqual(merged.source, .userEntered)
    }

    func testStoreClear_RemovesPersistedValue() {
        _ = PerformanceThresholdsStore.merge(ftpWatts: 210)
        PerformanceThresholdsStore.clear()
        XCTAssertNil(PerformanceThresholdsStore.load())
    }
}
