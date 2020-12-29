import CoreLocation

protocol AblyPublisherServiceDelegate: AnyObject {
    func publisherService(sender: AblyPublisherService, didChangeConnectionState state: ConnectionState)
    func publisherService(sender: AblyPublisherService, didFailWithError error: Error)
}

protocol AblyPublisherService: AnyObject {
    var delegate: AblyPublisherServiceDelegate? { get set }

    func track(trackable: Trackable, completion: ((Error?) -> Void)?)
    func stopTracking(trackable: Trackable, onSuccess: @escaping (_ wasPresent: Bool) -> Void, onError: @escaping ErrorHandler)
    func sendRawAssetLocation(location: CLLocation, completion: ((Error?) -> Void)?)
    func sendEnhancedAssetLocation(location: CLLocation, completion: ((Error?) -> Void)?)
    func stop()
}
