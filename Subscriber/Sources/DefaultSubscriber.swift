import Foundation
import CoreLocation

public class DefaultSubscriber: AssetTrackingSubscriber {
    private let configuration: AssetTrackingSubscriberConfiguration
    private let trackable: Trackable
    private let ablyService: AblySubscriberService
    
    public var delegate: AssetTrackingSubscriberDelegate?
    
    /**
     Default constructor. Initializes Subscriber with given `AssetTrackingSubscriberConfiguration`.
     Subscriber starts listening (and notifying delegate) after initialization.
     - Parameters:
        -  configuration: Configuration struct to use in this instance.
        - trackable: Asset to track.
     */
    public init(configuration: AssetTrackingSubscriberConfiguration,
                trackable: Trackable) {
        self.configuration = configuration
        self.trackable = trackable
        self.ablyService = AblySubscriberService(apiKey: configuration.apiKey,
                                                 clientId: configuration.clientId,
                                                 trackable: trackable)
        self.ablyService.delegate = self
    }
    
    public func start() {
        ablyService.start { [weak self] error in
            if let error = error,
               let strongSelf = self {
                strongSelf.delegate?.assetTrackingSubscriber(sender: strongSelf, didFailWithError: error)
            }
        }
    }
    
    public func stop() {
        ablyService.stop()
    }
}

extension DefaultSubscriber: AblySubscriberServiceDelegate {
    func subscriberService(sender: AblySubscriberService, didChangeAssetConnectionStatus status: AssetTrackingConnectionStatus) {
        delegate?.assetTrackingSubscriber(sender: self, didChangeAssetConnectionStatus: status)
    }
    
    func subscriberService(sender: AblySubscriberService, didFailWithError error: Error) {
        delegate?.assetTrackingSubscriber(sender: self, didFailWithError: error)
    }
    
    func subscriberService(sender: AblySubscriberService, didReceiveRawLocation location: CLLocation) {
        delegate?.assetTrackingSubscriber(sender: self, didUpdateRawLocation: location)
    }
    
    func subscriberService(sender: AblySubscriberService, didReceiveEnhancedLocation location: CLLocation) {
        delegate?.assetTrackingSubscriber(sender: self, didUpdateEnhancedLocation: location)
    }
}
