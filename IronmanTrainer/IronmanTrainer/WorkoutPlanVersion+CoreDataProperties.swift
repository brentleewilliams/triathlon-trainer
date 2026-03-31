import Foundation
import CoreData

extension WorkoutPlanVersion {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<WorkoutPlanVersion> {
        return NSFetchRequest<WorkoutPlanVersion>(entityName: "WorkoutPlanVersion")
    }

    @NSManaged public var changeDescription: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isCurrent: Bool
    @NSManaged public var source: String?
    @NSManaged public var weeklyPlanData: Data?

}

extension WorkoutPlanVersion: Identifiable {

}
