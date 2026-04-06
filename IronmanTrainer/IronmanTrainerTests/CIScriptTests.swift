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

    // MARK: - No Secrets in Git-Tracked Files

    /// Scan all git-tracked files for real API key patterns.
    /// Catches accidental commits of credentials.
    func testNoAPIKeysInTrackedFiles() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        // Enumerate source files in the project directory
        let projectDir = repoRoot.appendingPathComponent("IronmanTrainer")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: projectDir, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate project directory")
            return
        }

        var trackedFiles: [String] = []
        while let url = enumerator.nextObject() as? URL {
            let path = url.path
            // Skip build artifacts, DerivedData, .git, dependencies, etc.
            if path.contains("DerivedData") || path.contains(".git/") || path.contains(".build/") { continue }
            if path.contains("xcuserdata") || path.contains("xcshareddata/xcschemes") { continue }
            if path.contains("node_modules") || path.contains("Pods/") || path.contains(".framework/") { continue }
            trackedFiles.append(url.path)
        }

        // Patterns that indicate real API keys (not placeholders or variable references)
        let keyPatterns: [(name: String, pattern: String)] = [
            ("Anthropic API key", #"sk-ant-api\d{2}-[A-Za-z0-9_-]{20,}"#),
            ("LangSmith API key", #"lsv2_pt_[A-Za-z0-9]{20,}"#),
            ("Firebase/Google API key", #"AIzaSy[A-Za-z0-9_-]{33}"#),
            ("Generic Bearer token", #"Bearer [A-Za-z0-9_-]{20,}"#),
            ("AWS Access Key", #"AKIA[0-9A-Z]{16}"#),
            ("Generic secret key", #"(?i)(?:secret|password|token)\s*[:=]\s*[\"'][A-Za-z0-9_-]{16,}[\"']"#),
        ]

        var violations: [String] = []

        for filePath in trackedFiles {
            // Skip binary files and assets
            let ext = (filePath as NSString).pathExtension.lowercased()
            guard ["swift", "plist", "json", "sh", "xcconfig", "md", "js", "txt", "yaml", "yml", "xml"].contains(ext) else { continue }
            // Skip Config.local.xcconfig (gitignored, local-only)
            if filePath.contains("Config.local.xcconfig") { continue }

            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let relativePath = filePath.replacingOccurrences(of: projectDir.path + "/", with: "")

            for (name, pattern) in keyPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, range: range)

                for match in matches {
                    guard let matchRange = Range(match.range, in: content) else { continue }
                    let matched = String(content[matchRange])
                    let preview = String(matched.prefix(12)) + "..."
                    violations.append("\(relativePath): \(name) found (\(preview))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "API keys found in git-tracked files:\n" + violations.joined(separator: "\n"))
    }
}
