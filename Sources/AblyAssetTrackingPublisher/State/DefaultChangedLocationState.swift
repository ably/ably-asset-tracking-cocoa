//
//  Created by Łukasz Szyszkowski on 10/09/2021.
//

import Foundation

class DefaultChangedLocationState: PublisherChangedLocationState {
    private var closures: [WrappedClosure] = []
    var isEmpty: Bool {
        closures.isEmpty
    }
    
    func append(_ closure: WrappedClosure) {
        closures.append(closure)
    }
    
    func apply() {
        closures.forEach { wrappedClosure in
            wrappedClosure.apply()
        }
        clear()
    }
    
    func clear() {
        closures.removeAll()
    }
}
