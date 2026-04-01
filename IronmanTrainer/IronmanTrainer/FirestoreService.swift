import Foundation
import FirebaseFirestore

class FirestoreService: ObservableObject {
    static let shared = FirestoreService()

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Date Encoding

    /// Shared encoder that stores Dates as ISO 8601 strings for Firestore compatibility.
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    /// Converts a Codable value to a Firestore-compatible dictionary.
    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try Self.encoder.encode(value)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirestoreServiceError.encodingFailed
        }
        return dict
    }

    /// Decodes a Firestore document dictionary into a Codable type.
    private func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try Self.decoder.decode(T.self, from: data)
    }

    // MARK: - User Profile

    func saveUserProfile(_ profile: UserProfile) async throws {
        let dict = try encode(profile)
        try await db.collection("users").document(profile.uid).setData(dict, merge: true)
    }

    func getUserProfile(uid: String) async throws -> UserProfile? {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        guard let data = snapshot.data() else { return nil }
        return try decode(UserProfile.self, from: data)
    }

    // MARK: - Race

    func saveRace(_ race: Race, for uid: String) async throws {
        let raceId = race.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .prefix(64)
        let dict = try encode(race)
        try await db.collection("users").document(uid)
            .collection("races").document(String(raceId)).setData(dict)
    }

    func getRace(for uid: String) async throws -> Race? {
        let snapshot = try await db.collection("users").document(uid)
            .collection("races")
            .order(by: "date", descending: false)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snapshot.documents.first else { return nil }
        return try decode(Race.self, from: doc.data())
    }

    // MARK: - Training Plan

    func saveTrainingPlan(
        _ weeks: [TrainingWeek],
        metadata: PlanMetadata,
        for uid: String
    ) async throws {
        let planId = metadata.raceId ?? "active"
        let payload: [String: Any] = [
            "metadata": try encode(metadata),
            "weeks": try weeks.map { try encode($0) }
        ]
        try await db.collection("users").document(uid)
            .collection("plans").document(planId).setData(payload)
    }

    func getTrainingPlan(
        for uid: String
    ) async throws -> (weeks: [TrainingWeek], metadata: PlanMetadata)? {
        let snapshot = try await db.collection("users").document(uid)
            .collection("plans")
            .limit(to: 1)
            .getDocuments()
        guard let doc = snapshot.documents.first else { return nil }
        let data = doc.data()

        guard let metaDict = data["metadata"] as? [String: Any],
              let weeksArray = data["weeks"] as? [[String: Any]] else {
            throw FirestoreServiceError.decodingFailed
        }

        let metadata = try decode(PlanMetadata.self, from: metaDict)
        let weeks = try weeksArray.map { try decode(TrainingWeek.self, from: $0) }
        return (weeks: weeks, metadata: metadata)
    }
}

// MARK: - Errors

enum FirestoreServiceError: LocalizedError {
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode data for Firestore."
        case .decodingFailed: return "Failed to decode data from Firestore."
        }
    }
}
