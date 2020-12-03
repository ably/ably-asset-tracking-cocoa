//
//  AssetTrackingSubscriber.swift
//  Subscriber
//
//  Created by Michal Miedlarz on 03/12/2020.
//  Copyright © 2020 Ably. All rights reserved.
//

import UIKit
import CoreLocation

public enum AssetTrackingConnectionStatus {
    case online
    case offline
}

public protocol AssetTrackingSubscriberDelegate {
    /**
     Called when `AssetTrackingSubscriber` spot any (location, network or permissions) error
     - Parameters:
     - sender: `AssetTrackingSubscriber` instance.
     - error: Detected error.
     */
    func assetTrackingSubscriber(sender: AssetTrackingSubscriber, didFailWithError error: Error)
    
    /**
    Called when `AssetTrackingSubscriber` receive any Raw Location (received directly from location manager) update for observed trackable
     - Parameters:
     - sender: `AssetTrackingSubscriber` instance.
     - location: Received location.
     */
    func assetTrackingSubscriber(sender: AssetTrackingSubscriber, didUpdateRawLocation location: CLLocation)
    
    /**
    Called when `AssetTrackingSubscriber` receive any Enhanced Location (matched to road) update for observed trackable
     - Parameters:
     - sender: `AssetTrackingSubscriber` instance.
     - location: Received location.
     */
    func assetTrackingSubscriber(sender: AssetTrackingSubscriber, didUpdateEnhancedLocation location: CLLocation)
    
    /**
    Called when `AssetTrackingSubscriber` change connection status
     - Parameters:
     - sender: `AssetTrackingSubscriber` instance.
     - status: Updated connection status.
     */
    func assetTrackingSubscriber(sender: AssetTrackingSubscriber, didChangeConnectionStatus status: AssetTrackingConnectionStatus)
}

public protocol AssetTrackingSubscriber {
    /**
     Delegate object to receive events from `AssetTrackingSubscriber`.
     It holds a weak reference so make sure to keep your delegate object in memory.
     */
    var delegate: AssetTrackingSubscriberDelegate? { get set }
}
