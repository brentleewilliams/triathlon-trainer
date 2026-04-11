import Foundation

// MARK: - Trace Context

/// Passed from iOS → Cloud Function so the server-side LLM run
/// is created as a child of the client-initiated chain run.
/// Include these values as HTTP headers on the coaching request.
struct LangSmithTraceContext {
    let traceId: String      // shared UUID for the entire trace
    let runId: String        // this (parent chain) run's ID
    let dottedOrder: String  // parent dotted_order; server appends child segment
}

// MARK: - LangSmith Tracer

/// Traces coaching conversations to LangSmith via REST API.
///
/// Run hierarchy per coaching turn:
///   chain run "coaching_turn"   (client, this file)
///     └── llm run "llm_call"   (Cloud Function, functions/index.js)
///
/// Both runs share the same `trace_id`. The Cloud Function receives
/// the parent context via HTTP headers and creates its run as a child.
class LangSmithTracer {
    static let shared = LangSmithTracer()

    private let apiKey: String
    private let baseURL = "https://api.smith.langchain.com/runs"
    private let projectName = "IronmanTrainer"

    private init() {
        self.apiKey = Secrets.langsmithAPIKey
    }

    var isEnabled: Bool { !apiKey.isEmpty }

    // MARK: - Coaching Trace

    /// Creates a parent "chain" run for one coaching turn.
    /// Returns a `LangSmithTraceContext` that must be forwarded to the
    /// Cloud Function (via HTTP headers) so it can attach its LLM run
    /// as a child of this trace.
    func startCoachingTrace(userId: String?, userMessage: String) -> LangSmithTraceContext? {
        guard isEnabled else { return nil }

        let traceId = newUUID()
        // Root run: trace_id == run_id
        let runId = traceId
        let ts = dottedOrderTimestamp()
        let dottedOrder = "\(ts)Z\(traceId)"

        let body: [String: Any] = [
            "id": runId,
            "trace_id": traceId,
            "dotted_order": dottedOrder,
            "name": "coaching_turn",
            "run_type": "chain",
            "project_name": projectName,
            "session_name": userId ?? "anonymous",
            "start_time": isoNow(),
            "inputs": ["user_message": userMessage],
            "metadata": [
                "user_id": userId ?? "anonymous",
                "app_version": appVersion,
                "platform": "ios",
                "env": buildEnv
            ],
            "tags": buildTags
        ]

        Task { await post(body) }
        return LangSmithTraceContext(traceId: traceId, runId: runId, dottedOrder: dottedOrder)
    }

    /// Closes the parent chain run with the final coach response or error.
    func endCoachingTrace(_ context: LangSmithTraceContext?, response: String?, error: String?, toolCallMade: Bool = false) {
        guard isEnabled, let context else { return }

        var body: [String: Any] = [
            "end_time": isoNow(),
            "outputs": ["response": response ?? "", "tool_call_made": toolCallMade]
        ]
        if let error {
            body["error"] = error
            body["status"] = "error"
        }

        Task { await patch(runId: context.runId, body: body) }
    }

    // MARK: - Timestamp Helpers

    private func newUUID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Produces the timestamp segment used in LangSmith `dotted_order`.
    /// Format: YYYYMMDDTHHmmssSSSSSSZ  (microsecond precision, UTC)
    private func dottedOrderTimestamp() -> String {
        let now = Date()
        let interval = now.timeIntervalSince1970
        let micros = Int((interval - interval.rounded(.down)) * 1_000_000)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        return String(format: "%04d%02d%02dT%02d%02d%02d%06d",
            c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!, micros)
    }

    private func isoNow() -> String {
        Formatters.iso8601.string(from: Date())
    }

    // MARK: - Build Info

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildEnv: String {
        #if DEBUG
        return "development"
        #else
        return "beta"
        #endif
    }

    private var buildTags: [String] {
        #if DEBUG
        return ["ios", "development"]
        #else
        return ["ios", "beta"]
        #endif
    }

    // MARK: - HTTP

    private func post(_ body: [String: Any]) async {
        guard let url = URL(string: baseURL),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = data
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("[LangSmith] POST error: HTTP \(http.statusCode)")
            }
        } catch {
            print("[LangSmith] POST failed: \(error.localizedDescription)")
        }
    }

    private func patch(runId: String, body: [String: Any]) async {
        guard let url = URL(string: "\(baseURL)/\(runId)"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = data
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                print("[LangSmith] PATCH error: HTTP \(http.statusCode)")
            }
        } catch {
            print("[LangSmith] PATCH failed: \(error.localizedDescription)")
        }
    }
}
