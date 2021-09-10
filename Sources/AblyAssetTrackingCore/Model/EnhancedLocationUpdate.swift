import CoreLocation

/**
 Enumeration used to determine enhanced location type.
 */
public enum LocationUpdateType: String, Codable {
    case predicted = "PREDICTED"
    case actual = "ACTUAL"
}

/**
 Model used to handle location updates.
 */
public class EnhancedLocationUpdate {
    public let location: CLLocation
    public var skippedLocations: [CLLocation] = []

    public var type: LocationUpdateType {
        return .actual
    }

    public init(location: CLLocation) {
        self.location = location
    }
    
}

extension EnhancedLocationUpdate: Equatable {
    public static func == (lhs: EnhancedLocationUpdate, rhs: EnhancedLocationUpdate) -> Bool {
        lhs.location == rhs.location && lhs.skippedLocations == rhs.skippedLocations && lhs.type == rhs.type
    }
}
