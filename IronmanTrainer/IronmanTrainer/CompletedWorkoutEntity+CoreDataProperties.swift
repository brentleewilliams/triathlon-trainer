import Foundation
import CoreData

extension CompletedWorkoutEntity {
    @NSManaged public var weekNumber: Int32
    @NSManaged public var day: String?
    @NSManaged public var plannedType: String?
    @NSManaged public var completionDate: Date?
    @NSManaged public var hkWorkoutID: String?
    @NSManaged public var actualDuration: Double
    @NSManaged public var isManualOverride: Bool
    @NSManaged public var notes: String?

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CompletedWorkoutEntity> {
        return NSFetchRequest<CompletedWorkoutEntity>(entityName: "CompletedWorkoutEntity")
    }
}
