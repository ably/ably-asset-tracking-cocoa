//
//  Created by Łukasz Szyszkowski on 30/08/2021.
//

import Foundation

class DefaultSkippedLocatoinsState: PublisherSkippedLocationsState {
    
    let maxSkippedLocationsSize: Int
    private var skippedLocations: [String: [EnhancedLocationUpdate]] = [:]
    
    init(maxSkippedLocationsSize: Int = 60) {
        self.maxSkippedLocationsSize = maxSkippedLocationsSize
    }
    
    func add(trackableId: String, location: EnhancedLocationUpdate) {
        var locations = skippedLocations[trackableId] ?? []
        locations.append(location)
        if locations.count > maxSkippedLocationsSize {
            locations.remove(at: .zero)
        }
        skippedLocations[trackableId] = locations
    }
    
    func clear(trackableId: String) {
        skippedLocations[trackableId]?.removeAll()
    }
    
    func clearAll() {
        skippedLocations.removeAll()
    }
    
    func list(for trackableId: String) -> [EnhancedLocationUpdate] {
        skippedLocations[trackableId] ?? []
    }
}
