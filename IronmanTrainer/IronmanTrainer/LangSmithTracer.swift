import Foundation

// MARK: - LangSmith Tracer
class LangSmithTracer {
    static let shared = LangSmithTracer()

    private let langsmithAPIKey: String
    private let baseURL = "https://api.smith.langchain.com/runs"
    private let sessionName = "IronmanTrainer"

    init() {
        // Load API key from Secrets (Config.xcconfig)
        self.langsmithAPIKey = Secrets.langsmithAPIKey
    }

    func isEnabled() -> Bool {
        !langsmithAPIKey.isEmpty
    }

    func startRun(systemPrompt: String, userMessage: String) -> String {
        guard isEnabled() else { return "" }

        // LangSmith expects lowercase UUID format without dashes
        let runID = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let now = Formatters.iso8601.string(from: Date())

        let inputs: [String: Any] = [
            "system_prompt": systemPrompt,
            "user_message": userMessage
        ]

        let body: [String: Any] = [
            "id": runID,
            "name": "IronmanCoach",
            "run_type": "llm",
            "inputs": inputs,
            "start_time": now,
            "session_name": sessionName
        ]

        Task {
            await logRunToLangSmith(body)
        }

        return runID
    }

    func endRun(runID: String, response: String) {
        guard isEnabled() && !runID.isEmpty else { return }

        let now = Formatters.iso8601.string(from: Date())

        let outputs: [String: Any] = [
            "response": response
        ]

        let body: [String: Any] = [
            "outputs": outputs,
            "end_time": now
        ]

        Task {
            await updateRunInLangSmith(runID: runID, body: body)
        }
    }

    private func logRunToLangSmith(_ body: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    print("\u{2705} LangSmith run logged")
                } else {
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("\u{26A0}\u{FE0F} LangSmith error \(httpResponse.statusCode): \(errorText)")
                    } else {
                        print("\u{26A0}\u{FE0F} LangSmith error: \(httpResponse.statusCode)")
                    }
                }
            }
        } catch {
            print("\u{274C} LangSmith logging failed: \(error)")
        }
    }

    private func updateRunInLangSmith(runID: String, body: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        let updateURL = "\(baseURL)/\(runID)"
        var request = URLRequest(url: URL(string: updateURL)!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    print("\u{2705} LangSmith run completed")
                } else {
                    print("\u{26A0}\u{FE0F} LangSmith update error: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("\u{274C} LangSmith update failed: \(error)")
        }
    }
}
