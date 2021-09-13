//
//  Created by Łukasz Szyszkowski on 10/09/2021.
//

import Foundation

enum WrappedClosure {
    case tripStart(event: TripStartedEvent, closure: (TripStartedEvent) -> Void)
    case tripEnd(event: TripEndedEvent, closure: (TripEndedEvent) -> Void)
    
    func apply() {
        switch self {
        case let .tripStart(event, closure):
            closure(event)
        case let .tripEnd(event, closure):
            closure(event)
        }
    }
}

protocol PublisherChangedLocationState {
    var isEmpty: Bool { get }
    
    func append(_ closure: WrappedClosure)
    func apply()
    func clear()
}
