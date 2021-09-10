//
//  Created by Łukasz Szyszkowski on 08/09/2021.
//

import Foundation
@testable import AblyAssetTrackingPublisher

class TestableTrackableState: DefaultTrackableState {
    
    private var resetCounterWillCallClosure: (() -> Void)?
    private var resetCounterDidCallClosure: (() -> Void)?
    private var removeWillCallClosure: (() -> Void)?
    private var removeDidCallClosure: (() -> Void)?
    private var unmarkMessageAsPendingWillCallClosure: (() -> Void)?
    private var unmarkMessageAsPendingDidCallClosure: (() -> Void)?
    
    func resetCounterWillCall(_ closure: @escaping (() -> Void)) {
        resetCounterWillCallClosure = closure
    }
    
    func resetCounterDidCall(_ closure: @escaping (() -> Void)) {
        resetCounterDidCallClosure = closure
    }
    
    override func resetCounter(for trackableId: DefaultTrackableState.TrackableId) {
        resetCounterWillCallClosure?()
        super.resetCounter(for: trackableId)
        resetCounterDidCallClosure?()
    }
    
    func removeWillCall(_ closure: @escaping (() -> Void)) {
        removeWillCallClosure = closure
    }
    
    func removeDidCall(_ closure: @escaping (() -> Void)) {
        removeDidCallClosure = closure
    }
    
    override func remove(trackableId: DefaultTrackableState.TrackableId) {
        removeWillCallClosure?()
        super.remove(trackableId: trackableId)
        removeDidCallClosure?()
    }
    
    func unmarkMessageAsPendingWillCall(_ closure: @escaping (() -> Void)) {
        unmarkMessageAsPendingWillCallClosure = closure
    }
    
    func unmarkMessageAsPendingDidCall(_ closure: @escaping (() -> Void)) {
        unmarkMessageAsPendingDidCallClosure = closure
    }
    
    override func unmarkMessageAsPending(for trackableId: DefaultTrackableState.TrackableId) {
        unmarkMessageAsPendingWillCallClosure?()
        super.unmarkMessageAsPending(for: trackableId)
        unmarkMessageAsPendingDidCallClosure?()
    }
}
