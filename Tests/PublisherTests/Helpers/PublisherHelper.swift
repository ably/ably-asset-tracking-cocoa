import XCTest
import CoreLocation
import AblyAssetTrackingCore
import AblyAssetTrackingInternal
@testable import AblyAssetTrackingPublisher

class PublisherHelper {
    typealias TrackableStateable = StateWaitable & StatePendable & StateRemovable & StateRetryable & StateSkippable
    
    enum SendLocationResultPolicy {
        case success
        case retry
        case fail
    }
    
    private let defaultTimeout: TimeInterval
    private var addedTrackables: [String] = []
    
    init(defaultTimeout: TimeInterval = 5.0) {
        self.defaultTimeout = defaultTimeout
    }
        
    func sendLocationUpdate(
        ablyService: MockAblyPublisherService,
        publisher: DefaultPublisher,
        locationUpdate: EnhancedLocationUpdate,
        trackable: Trackable,
        trackableState: TrackableStateable,
        locationService: LocationService = MockLocationService(),
        resultPolicy: SendLocationResultPolicy = .success,
        error: ErrorInformation = ErrorInformation(type: .commonError(errorMessage: "Failure"))
    ) {
        /**
         Omit re-adding trackable
         */
        if !addedTrackables.contains(trackable.id) {
            /**
             Start publishing trackable
             */
            let connectCompletionHandlerExpectation = XCTestExpectation(description: "Track completion handler expectation")
            ablyService.connectCompletionHandler = { callback in
                callback?(.success)
                self.addedTrackables.append(trackable.id)
                connectCompletionHandlerExpectation.fulfill()
            }
            
            publisher.track(trackable: trackable) { _ in }
            
            switch XCTWaiter.wait(for: [connectCompletionHandlerExpectation], timeout: defaultTimeout) {
            case .timedOut:
                XCTFail("Timeout \(connectCompletionHandlerExpectation.description)")
            default: ()
            }
        }
        
        ablyService.sendEnhancedAssetLocationUpdateCounter = .zero
                
        let expectationDidSendEnhancedLocation = XCTestExpectation(description: "Publisher did send enhanced location")
        
        ablyService.sendEnhancedAssetLocationUpdateParamCompletionHandler = { completion in            
            switch resultPolicy {
            case .success:
                completion?(.success)
                expectationDidSendEnhancedLocation.fulfill()
            case .retry:
                if ablyService.sendEnhancedAssetLocationUpdateCounter == trackableState.maxRetryCount {
                    completion?(.failure(error))
                } else {
                    completion?(.success)
                    expectationDidSendEnhancedLocation.fulfill()
                }
            case .fail:
                completion?(.failure(error))
                if ablyService.sendEnhancedAssetLocationUpdateCounter == trackableState.maxRetryCount + 1 {
                    expectationDidSendEnhancedLocation.fulfill()
                }
            }
        }
        
        publisher.locationService(sender: locationService, didUpdateEnhancedLocationUpdate: locationUpdate)

        switch XCTWaiter.wait(for: [expectationDidSendEnhancedLocation], timeout: defaultTimeout) {
        case .timedOut:
            XCTFail("Timeout \(expectationDidSendEnhancedLocation.description)")
        default: ()
        }
    }
    
    static func createPublisher(
        ablyService: AblyPublisher,
        connectionConfiguration: ConnectionConfiguration = ConnectionConfiguration(apiKey: "API_KEY", clientId: "CLIENT_ID"),
        mapboxConfiguration: MapboxConfiguration = MapboxConfiguration(mapboxKey: "MAPBOX_ACCESS_TOKEN"),
        logConfiguration: LogConfiguration = LogConfiguration(),
        routingProfile: RoutingProfile = .driving,
        resolutionPolicyFactory: ResolutionPolicyFactory = MockResolutionPolicyFactory(),
        locationService: LocationService = MockLocationService(),
        routeProvider: RouteProvider = MockRouteProvider(),
        trackableState: TrackableStateable = TrackableState()
    ) -> DefaultPublisher {
        
        DefaultPublisher(
            connectionConfiguration: connectionConfiguration,
            mapboxConfiguration: mapboxConfiguration,
            logConfiguration: logConfiguration,
            routingProfile: routingProfile,
            resolutionPolicyFactory: resolutionPolicyFactory,
            ablyPublisher: ablyService,
            locationService: locationService,
            routeProvider: routeProvider,
            trackableState: trackableState
        )
    }
}
