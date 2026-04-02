import XCTest

/// Validates that ci_post_clone.sh writes files to paths that match
/// the actual project structure. Prevents path drift between the CI
/// script and the Xcode project layout.
final class CIScriptTests: XCTestCase {

    /// Parse the ci_post_clone.sh script and extract all output paths
    /// (lines matching `cat > "..."`) then verify each path's
    /// project-relative portion corresponds to a real file.
    func testCIScriptOutputPathsMatchProjectStructure() throws {
        // Find the repo root (two levels up from the .app bundle isn't reliable in tests,
        // so we walk up from the source file's known location via #filePath)
        let testFile = URL(fileURLWithPath: #filePath) // .../IronmanTrainerTests/CIScriptTests.swift
        let repoRoot = testFile
            .deletingLastPathComponent() // IronmanTrainerTests/
            .deletingLastPathComponent() // IronmanTrainer/ (project dir)
            .deletingLastPathComponent() // repo root

        let scriptURL = repoRoot
            .appendingPathComponent("IronmanTrainer")
            .appendingPathComponent("ci_scripts")
            .appendingPathComponent("ci_post_clone.sh")

        let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)

        // Extract paths from: cat > "$CI_PRIMARY_REPOSITORY_PATH/Some/Path" <<EOL
        // The regex captures the part after $CI_PRIMARY_REPOSITORY_PATH/
        let pattern = #"\$CI_PRIMARY_REPOSITORY_PATH/([^"]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: scriptContent, range: NSRange(scriptContent.startIndex..., in: scriptContent))

        XCTAssertGreaterThan(matches.count, 0, "Should find at least one output path in ci_post_clone.sh")

        for match in matches {
            guard let range = Range(match.range(at: 1), in: scriptContent) else { continue }
            let relativePath = String(scriptContent[range])

            let fullPath = repoRoot.appendingPathComponent(relativePath)
            let exists = FileManager.default.fileExists(atPath: fullPath.path)

            XCTAssertTrue(exists, "CI script writes to '\(relativePath)' but that path does not exist in the project. Fix ci_post_clone.sh to use the correct path.")
        }
    }

    /// Verify the script references the expected set of files
    func testCIScriptWritesAllRequiredConfigFiles() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let scriptURL = repoRoot
            .appendingPathComponent("IronmanTrainer")
            .appendingPathComponent("ci_scripts")
            .appendingPathComponent("ci_post_clone.sh")

        let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(scriptContent.contains("Config.plist"), "CI script must generate Config.plist")
        XCTAssertTrue(scriptContent.contains("Config.local.xcconfig"), "CI script must generate Config.local.xcconfig")
        XCTAssertTrue(scriptContent.contains("GoogleService-Info.plist"), "CI script must generate GoogleService-Info.plist")
        XCTAssertTrue(scriptContent.contains("ANTHROPICAPIKEY"), "CI script must reference ANTHROPICAPIKEY env var")
        XCTAssertTrue(scriptContent.contains("LANGSMITHAPIKEY"), "CI script must reference LANGSMITHAPIKEY env var")
    }
}
