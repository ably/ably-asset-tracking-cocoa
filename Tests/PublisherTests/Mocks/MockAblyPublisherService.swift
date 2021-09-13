import CoreLocation
import Foundation
import AblyAssetTrackingCore
@testable import AblyAssetTrackingPublisher

class MockAblyPublisherService: AblyPublisherService {
    var trackCalled: Bool = false
    var trackParamTrackable: Trackable?
    var trackParamResultHandler: ResultHandler<Void>?
    var trackCompletionHandler: ((ResultHandler<Void>?) -> Void)?
    func track(trackable: Trackable, completion: ResultHandler<Void>?) {
        trackCalled = true
        trackParamTrackable = trackable
        trackParamResultHandler = completion
        trackCompletionHandler?(completion)
    }
    
    var stopTrackingCalled: Bool = false
    var stopTrackingParamTrackable: Trackable?
    var stopTrackingParamResultHandler: ResultHandler<Bool>?
    var stopTrackingResultCompletionHandler: ((ResultHandler<Bool>?) -> Void)?
    func stopTracking(trackable: Trackable, completion: ResultHandler<Bool>?) {
        stopTrackingCalled = true
        stopTrackingParamTrackable = trackable
        stopTrackingParamResultHandler = completion
        
        stopTrackingResultCompletionHandler?(completion)
    }

    var wasDelegateSet: Bool = false
    var delegate: AblyPublisherServiceDelegate? {
        didSet { wasDelegateSet = true }
    }

    var sendEnhancedAssetLocationUpdateCounter: Int = .zero
    var sendEnhancedAssetLocationUpdateCalled: Bool = false
    var sendEnhancedAssetLocationUpdateParamLocationUpdate: EnhancedLocationUpdate?
    var sendEnhancedAssetLocationUpdateParamTrackable: Trackable?
    var sendEnhancedAssetLocationUpdateParamCompletion: ResultHandler<Void>?
    var sendEnhancedAssetLocationUpdateParamCompletionHandler: ((ResultHandler<Void>?) -> Void)?
    func sendEnhancedAssetLocationUpdate(locationUpdate: EnhancedLocationUpdate, forTrackable trackable: Trackable, completion: ResultHandler<Void>?) {
        sendEnhancedAssetLocationUpdateCounter += 1
        sendEnhancedAssetLocationUpdateCalled = true
        sendEnhancedAssetLocationUpdateParamLocationUpdate = locationUpdate
        sendEnhancedAssetLocationUpdateParamTrackable = trackable
        sendEnhancedAssetLocationUpdateParamCompletion = completion
        sendEnhancedAssetLocationUpdateParamCompletionHandler?(completion)
    }
    
    
    var closeCalled: Bool = false
    var closeParamCompletion: ResultHandler<Void>?
    var closeResultCompletionHandler: ((ResultHandler<Void>?) -> Void)?
    func close(completion: @escaping ResultHandler<Void>) {
        closeCalled = true
        closeParamCompletion = completion
        closeResultCompletionHandler?(completion)
    }
    
    var sendTripStartMetadataCalled: Bool = false
    var sendTripStartMetadataParam: TripMetadata?
    var sendTripStartMetadataHandler: (() -> Void)?
    func sendTripStartMetadata(metadata: TripMetadata) {
        sendTripStartMetadataCalled = true
        sendTripStartMetadataParam = metadata
        
        sendTripStartMetadataHandler?()
    }
    
    var sendTripEndMetadataCalled: Bool = false
    var sendTripEndMetadataParam: TripMetadata?
    var sendTripEndMetadataHandler: (() -> Void)?
    func sendTripEndMetadata(metadata: TripMetadata) {
        sendTripEndMetadataCalled = true
        sendTripEndMetadataParam = metadata
        
        sendTripEndMetadataHandler?()
    }
}
