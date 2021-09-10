//
//  File.swift
//  
//
//  Created by Łukasz Szyszkowski on 25/08/2021.
//

import Foundation
import AblyAssetTrackingCore

protocol PublisherTrackableState {
    typealias TrackableId = String
    
    mutating func remove(trackableId: TrackableId)
    mutating func removeAll()
    /**
     Retry
     */
    var maxRetryCount: Int { get }
    mutating func resetCounter(for trackableId: TrackableId)
    mutating func incrementCounter(for trackableId: TrackableId)
    mutating func shouldRetry(trackableId: TrackableId) -> Bool
    func getCounter(for trackableId: TrackableId) -> Int
    /**
     Pending message
     */
    mutating func markMessageAsPending(for trackableId: TrackableId)
    mutating func unmarkMessageAsPending(for trackableId: TrackableId)
    func hasPendingMessage(for trackableId: TrackableId) -> Bool
    /**
     Waiting
     */
    mutating func addToWaiting(locationUpdate: EnhancedLocationUpdate, for trackableId: TrackableId)
    mutating func nextWaiting(for trackableId: TrackableId) -> EnhancedLocationUpdate?
}
