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

        guard let url = URL(string: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 && httpResponse.statusCode != 202 {
                print("[LANGSMITH] Log error: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("[LANGSMITH] Log failed: \(error.localizedDescription)")
        }
    }

    private func updateRunInLangSmith(runID: String, body: [String: Any]) async {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        let updateURL = "\(baseURL)/\(runID)"
        guard let url = URL(string: updateURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(langsmithAPIKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 && httpResponse.statusCode != 202 {
                print("[LANGSMITH] Update error: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            print("[LANGSMITH] Update failed: \(error.localizedDescription)")
        }
    }
}
