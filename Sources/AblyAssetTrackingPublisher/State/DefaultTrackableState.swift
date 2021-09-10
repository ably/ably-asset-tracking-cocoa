//
//  Created by Łukasz Szyszkowski on 30/08/2021.
//

import Foundation
import AblyAssetTrackingCore

class DefaultTrackableState: PublisherTrackableState {
    
    let maxRetryCount: Int
    private var retryCounter: [TrackableId: Int] = [:]
    private var pendingMessages: Set<TrackableId> = []
    private var waitingLocationUpdates: [TrackableId: [EnhancedLocationUpdate]] = [:]
    
    init(maxRetryCount: Int = 1) {
        self.maxRetryCount = maxRetryCount
    }
    
    func shouldRetry(trackableId: TrackableId) -> Bool {
        addIfNeeded(trackableId: trackableId)
        
        return getCounter(for: trackableId) < maxRetryCount
    }
    
    func resetCounter(for trackableId: TrackableId) {
        guard retryCounter[trackableId] != nil else {
            return
        }
        
        retryCounter[trackableId] = .zero
    }
    
    func incrementCounter(for trackableId: TrackableId) {
        retryCounter[trackableId] = getCounter(for: trackableId) + 1
    }
    
    func getCounter(for trackableId: TrackableId) -> Int {
        retryCounter[trackableId] ?? .zero
    }
    
    private func addIfNeeded(trackableId: TrackableId) {
        guard retryCounter[trackableId] == nil else {
            return
        }
        
        retryCounter[trackableId] = .zero
    }
    
    func markMessageAsPending(for trackableId: TrackableId) {
        pendingMessages.insert(trackableId)
    }
    
    func unmarkMessageAsPending(for trackableId: TrackableId) {
        pendingMessages.remove(trackableId)
        retryCounter.removeValue(forKey: trackableId)
    }
    
    func hasPendingMessage(for trackableId: TrackableId) -> Bool {
        pendingMessages.contains(trackableId)
    }
    
    func addToWaiting(locationUpdate: EnhancedLocationUpdate, for trackableId: TrackableId) {
        var locations = waitingLocationUpdates[trackableId] ?? []
        locations.append(locationUpdate)
        waitingLocationUpdates[trackableId] = locations
    }
    
    func nextWaiting(for trackableId: TrackableId) -> EnhancedLocationUpdate? {
        guard var enhancedLocationUpdates = waitingLocationUpdates[trackableId], !enhancedLocationUpdates.isEmpty else {
            return nil
        }
        
        let location = enhancedLocationUpdates.removeFirst()
        waitingLocationUpdates[trackableId] = enhancedLocationUpdates
        
        return location
    }
    
    func remove(trackableId: TrackableId) {
        retryCounter.removeValue(forKey: trackableId)
        pendingMessages.remove(trackableId)
        waitingLocationUpdates.removeValue(forKey: trackableId)
    }
    
    func removeAll() {
        retryCounter.removeAll()
        pendingMessages.removeAll()
        waitingLocationUpdates.removeAll()
    }
}
