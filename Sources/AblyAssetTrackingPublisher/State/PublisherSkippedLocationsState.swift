//
//  Created by Łukasz Szyszkowski on 30/08/2021.
//

import Foundation 

protocol PublisherSkippedLocationsState {
    func add(trackableId: String, location: EnhancedLocationUpdate)
    func clear(trackableId: String)
    func clearAll()
    func list(for trackableId: String) -> [EnhancedLocationUpdate]
}
