import UIKit
import CoreLocation
import Logging
import MapboxDirections
import AblyAssetTrackingCore
import AblyAssetTrackingInternal

// Default logger used in Publisher SDK
let logger: Logger = Logger(label: "com.ably.tracking.Publisher")

// swiftlint:disable cyclomatic_complexity
class DefaultPublisher: Publisher {
    // Publisher state
    private enum State {
        case working
        case stopping
        case stopped

        var isStoppingOrStopped: Bool {
            self == .stopping || self == .stopped
        }
    }
    
    private let workingQueue: DispatchQueue
    private let connectionConfiguration: ConnectionConfiguration
    private let mapboxConfiguration: MapboxConfiguration
    private let logConfiguration: LogConfiguration
    private let locationService: LocationService
    private let ablyService: AblyPublisherService
    private let resolutionPolicy: ResolutionPolicy
    private let routeProvider: RouteProvider
    private let batteryLevelProvider: BatteryLevelProvider
    private var trackableState: PublisherTrackableState
    private var skippedLocationsState: PublisherSkippedLocationsState
    private var state: State = .working

    // ResolutionPolicy
    private let hooks: DefaultResolutionPolicyHooks
    private let methods: DefaultResolutionPolicyMethods
    private var proximityThreshold: Proximity?
    private var proximityHandler: ProximityHandler?
    private var requests: [Trackable: [Subscriber: Resolution]]
    private var subscribers: [Trackable: Set<Subscriber>]
    private var resolutions: [Trackable: Resolution]
    private var locationEngineResolution: Resolution
    private var trackables: Set<Trackable>

    private var lastEnhancedLocations: [Trackable: CLLocation]
    private var lastEnhancedTimestamps: [Trackable: Date]
    private var route: Route?

    private var receivedAblyClientConnectionState: ConnectionState = .offline
    private var receivedAblyChannelsConnectionStates: [Trackable: ConnectionState] = [:]
    private var currentTrackablesConnectionStates: [Trackable: ConnectionState] = [:]

    public weak var delegate: PublisherDelegate?
    public weak var delegateObjectiveC: PublisherDelegateObjectiveC?
    private(set) public var activeTrackable: Trackable?
    private(set) public var routingProfile: RoutingProfile

    init(connectionConfiguration: ConnectionConfiguration,
         mapboxConfiguration: MapboxConfiguration,
         logConfiguration: LogConfiguration,
         routingProfile: RoutingProfile,
         resolutionPolicyFactory: ResolutionPolicyFactory,
         ablyService: AblyPublisherService,
         locationService: LocationService,
         routeProvider: RouteProvider,
         trackableState: PublisherTrackableState = DefaultTrackableState(),
         skippedLocationsState: PublisherSkippedLocationsState = DefaultSkippedLocationsState()
    ) {
        
        self.connectionConfiguration = connectionConfiguration
        self.mapboxConfiguration = mapboxConfiguration
        self.logConfiguration = logConfiguration
        self.routingProfile = routingProfile
        self.workingQueue = DispatchQueue(label: "io.ably.asset-tracking.Publisher.DefaultPublisher", qos: .default)
        self.locationService = locationService
        self.ablyService = ablyService
        self.routeProvider = routeProvider
        self.trackableState = trackableState
        self.skippedLocationsState = skippedLocationsState

        self.batteryLevelProvider = DefaultBatteryLevelProvider()

        self.hooks = DefaultResolutionPolicyHooks()
        self.methods = DefaultResolutionPolicyMethods()
        self.resolutionPolicy = resolutionPolicyFactory.createResolutionPolicy(hooks: hooks, methods: methods)
        self.locationEngineResolution = resolutionPolicy.resolve(resolutions: [])

        self.requests = [:]
        self.subscribers = [:]
        self.resolutions = [:]
        self.lastEnhancedLocations = [:]
        self.lastEnhancedTimestamps = [:]
        self.trackables = []

        self.ablyService.delegate = self
        self.locationService.delegate = self
        self.methods.delegate = self
    }

    func track(trackable: Trackable, completion: @escaping ResultHandler<Void>) {
        let event = TrackTrackableEvent(trackable: trackable,
                                        resultHandler: completion)
        enqueue(event: event)
    }

    func add(trackable: Trackable, completion: @escaping ResultHandler<Void>) {
        let event = AddTrackableEvent(trackable: trackable, resultHandler: completion)
        enqueue(event: event)
    }

    func remove(trackable: Trackable, completion: @escaping ResultHandler<Bool>) {
         let event = RemoveTrackableEvent(trackable: trackable, resultHandler: completion)
         enqueue(event: event)
    }

    func changeRoutingProfile(profile: RoutingProfile, completion: @escaping ResultHandler<Void>) {
        let event = ChangeRoutingProfileEvent(profile: profile, resultHandler: completion)
        enqueue(event: event)
    }

    func stop(completion: @escaping ResultHandler<Void>) {
        enqueue(event: StopEvent(resultHandler: completion))
    }
}

extension DefaultPublisher: PublisherObjectiveC {
    @objc
    func track(trackable: Trackable, onSuccess: @escaping (() -> Void), onError: @escaping ((ErrorInformation) -> Void)) {
        self.track(trackable: trackable) { result in
            switch result {
            case .success:
                onSuccess()
            case .failure(let error):
                onError(error)
            }
        }
    }

    @objc
    func add(trackable: Trackable, onSuccess: @escaping (() -> Void), onError: @escaping ((ErrorInformation) -> Void)) {
        self.add(trackable: trackable) { result in
            switch result {
            case .success:
                onSuccess()
            case .failure(let error):
                onError(error)
            }
        }
    }

    @objc
    func remove(trackable: Trackable, onSuccess: @escaping ((Bool) -> Void), onError: @escaping ((ErrorInformation) -> Void)) {
        self.remove(trackable: trackable) { result in
            switch result {
            case .success(let wasPresent):
                onSuccess(wasPresent)
            case .failure(let error):
                onError(error)
            }
        }
    }

    @objc
    func changeRoutingProfile(profile: RoutingProfile, onSuccess: @escaping (() -> Void), onError: @escaping ((ErrorInformation) -> Void)) {
        self.changeRoutingProfile(profile: profile) { result in
            switch result {
            case .success:
                onSuccess()
            case .failure(let error):
                onError(error)
            }
        }
    }

    @objc
    func stop(onSuccess: @escaping (() -> Void), onError: @escaping ((ErrorInformation) -> Void)) {
        self.stop { result in
            switch result {
            case .success:
                onSuccess()
            case .failure(let error):
                onError(error)
            }
        }
    }
}

// MARK: Threading events handling
extension DefaultPublisher {
    private func enqueue(event: PublisherEvent) {
        logger.trace("Received event: \(event)")
        performOnWorkingThread { [weak self] in
            switch event {
            case let event as TrackTrackableEvent: self?.performTrackTrackableEvent(event)
            case let event as PresenceJoinedSuccessfullyEvent: self?.performPresenceJoinedSuccessfullyEvent(event)
            case let event as TripStartEvent: self?.performTripStartEvent(event)
            case let event as TripEndEvent: self?.performTripEndEvent(event)
            case let event as TrackableReadyToTrackEvent: self?.performTrackableReadyToTrack(event)
            case let event as EnhancedLocationChangedEvent: self?.performEnhancedLocationChanged(event)
            case let event as SendEnhancedLocationSuccessEvent: self?.performSendEnhancedLocationSuccess(event)
            case let event as SendEnhancedLocationFailureEvent: self?.performSendEnhancedLocationFailure(event)
            case let event as AddTrackableEvent: self?.performAddTrackableEvent(event)
            case let event as RemoveTrackableEvent: self?.performRemoveTrackableEvent(event)
            case let event as ClearActiveTrackableEvent: self?.performClearActiveTrackableEvent(event)
            case let event as RefreshResolutionPolicyEvent: self?.performRefreshResolutionPolicyEvent(event)
            case let event as ChangeLocationEngineResolutionEvent: self?.performChangeLocationEngineResolutionEvent(event)
            case let event as PresenceUpdateEvent: self?.performPresenceUpdateEvent(event)
            case let event as ClearRemovedTrackableMetadataEvent: self?.performClearRemovedTrackableMetadataEvent(event)
            case let event as SetDestinationSuccessEvent: self?.performSetDestinationSuccessEvent(event)
            case let event as DelegateResolutionUpdateEvent: self?.notifyDelegateResolutionUpdate(event)
            case let event as DelegateErrorEvent: self?.notifyDelegateDidFailWithError(event.error)
            case let event as DelegateTrackableConnectionStateChangedEvent: self?.notifyDelegateConnectionStateChanged(event)
            case let event as DelegateEnhancedLocationChangedEvent: self?.notifyDelegateEnhancedLocationChanged(event)
            case let event as ChangeRoutingProfileEvent: self?.performChangeRoutingProfileEvent(event)
            case let event as StopEvent: self?.performStopPublisherEvent(event)
            case let event as AblyConnectionClosedEvent: self?.performAblyConnectionClosedEvent(event)
            case let event as AblyClientConnectionStateChangedEvent: self?.performAblyClientConnectionChangedEvent(event)
            case let event as AblyChannelConnectionStateChangedEvent: self?.performAblyChannelConnectionStateChangedEvent(event)
            default: preconditionFailure("Unhandled event in DefaultPublisher: \(event) ")
            }
        }
    }

    private func callback<T: Any>(value: T, handler: @escaping ResultHandler<T>) {
        performOnMainThread { handler(.success(value)) }
    }

    private func callback<T: Any>(error: ErrorInformation, handler: @escaping ResultHandler<T>) {
        performOnMainThread { handler(.failure(error)) }
    }

    private func publisherStoppedCallback<T: Any>(handler: @escaping ResultHandler<T>) {
        let error = ErrorInformation(type: .publisherStoppedException)
        performOnMainThread { handler(.failure(error)) }
    }

    private func callback(event: PublisherDelegateEvent) {
        logger.trace("Received delegate event: \(event)")

        performOnMainThread { [weak self] in
            guard let self = self
            else { return }

            switch event {
            case let event as DelegateErrorEvent:
                self.delegate?.publisher(sender: self, didFailWithError: event.error)
                self.delegateObjectiveC?.publisher(sender: self, didFailWithError: event.error)
            case let event as DelegateTrackableConnectionStateChangedEvent:
                self.delegate?.publisher(sender: self, didChangeConnectionState: event.connectionState, forTrackable: event.trackable)
                self.delegateObjectiveC?.publisher(sender: self, didChangeConnectionState: event.connectionState)
            case let event as DelegateEnhancedLocationChangedEvent:
                self.delegate?.publisher(sender: self, didUpdateEnhancedLocation: event.locationUpdate.location)
                self.delegateObjectiveC?.publisher(sender: self, didUpdateEnhancedLocation: event.locationUpdate.location)
            default: preconditionFailure("Unhandled delegate event in DefaultPublisher: \(event) ")
            }
        }
    }

    // MARK: Track
    // swiftlint:disable line_length
    private func performTrackTrackableEvent(_ event: TrackTrackableEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        guard !trackables.contains(event.trackable) else {
            let error = ErrorInformation(type: .trackableAlreadyExist(trackableId: event.trackable.id))
            callback(error: error, handler: event.resultHandler)
            return
        }

        self.ablyService.track(trackable: event.trackable) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.callback(error: error, handler: event.resultHandler)
                return
            case .success:
                self?.enqueue(event: PresenceJoinedSuccessfullyEvent(trackable: event.trackable) { [weak self] result in
                    switch result {
                    case .success:
                        self?.enqueue(event: TrackableReadyToTrackEvent(trackable: event.trackable, resultHandler: event.resultHandler))
                    default:
                        return
                    }
                })
            }
        }
    }

    private func performTrackableReadyToTrack(_ event: TrackableReadyToTrackEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        if activeTrackable != event.trackable {
            activeTrackable = event.trackable
            hooks.trackables?.onActiveTrackableChanged(trackable: event.trackable)
            if let destination = event.trackable.destination {
                routeProvider.getRoute(to: destination, withRoutingProfile: routingProfile) { [weak self] result in
                    switch result {
                    case .success(let route):
                        self?.enqueue(event: SetDestinationSuccessEvent(route: route))
                    case .failure(let error):
                        logger.error("Can't fetch route. Error: \(error.message)")
                        event.resultHandler(.failure(error))
                    }
                }
            } else {
                self.route = nil
            }
        }

        callback(value: Void(), handler: event.resultHandler)
    }

    private func performPresenceJoinedSuccessfullyEvent(_ event: PresenceJoinedSuccessfullyEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        trackables.insert(event.trackable)
        locationService.startUpdatingLocation()
        resolveResolution(trackable: event.trackable)
        hooks.trackables?.onTrackableAdded(trackable: event.trackable)
        event.resultHandler(.success)
        enqueue(event: TripStartEvent(trackable: event.trackable))
    }
    
    private func performTripStartEvent(_ event: TripStartEvent) {
        sendStartTripMetadata(trackable: event.trackable)
    }
    
    private func performTripEndEvent(_ event: TripEndEvent) {
        sendEndTripMetadata(trackable: event.trackable)
    }

    // MARK: RoutingProfile
    private func performChangeRoutingProfileEvent(_ event: ChangeRoutingProfileEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        routeProvider.changeRoutingProfile(to: routingProfile) { [weak self] result in
            switch result {
            case .success(let route):
                self?.routingProfile = event.profile
                self?.enqueue(event: SetDestinationSuccessEvent(route: route))
                self?.callback(value: Void(), handler: event.resultHandler)
            case .failure(let error):
                logger.error("Can't change RoutingProfile. Error: \(error)")
                self?.callback(error: error, handler: event.resultHandler)
            }
        }
    }

    // MARK: Destination
    private func performSetDestinationSuccessEvent(_ event: SetDestinationSuccessEvent) {
        self.route = event.route
    }

    // MARK: Add trackable
    private func performAddTrackableEvent(_ event: AddTrackableEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        guard !trackables.contains(event.trackable) else {
            let error = ErrorInformation(type: .trackableAlreadyExist(trackableId: event.trackable.id))
            callback(error: error, handler: event.resultHandler)
            return
        }

        self.ablyService.track(trackable: event.trackable) { [weak self] result in
            switch result {
            case .success:
                self?.enqueue(event: PresenceJoinedSuccessfullyEvent(trackable: event.trackable) { [weak self] _ in
                    self?.callback(value: Void(), handler: event.resultHandler)
                })
            case .failure(let error):
                self?.callback(error: error, handler: event.resultHandler)
            }
        }
    }

    // MARK: Remove trackable
    private func performRemoveTrackableEvent(_ event: RemoveTrackableEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        self.ablyService.stopTracking(trackable: event.trackable) { [weak self] result in
            switch result {
            case .success(let wasPresent):
                self?.trackableState.remove(trackableId: event.trackable.id)
                wasPresent
                    ? self?.enqueue(event: ClearRemovedTrackableMetadataEvent(trackable: event.trackable, resultHandler: event.resultHandler))
                    : self?.callback(value: false, handler: event.resultHandler)
                self?.enqueue(event: TripEndEvent(trackable: event.trackable))
            case .failure(let error):
                self?.callback(error: error, handler: event.resultHandler)
            }
        }
    }

    // MARK: Stop publisher
    private func performStopPublisherEvent(_ event: StopEvent) {
        if state.isStoppingOrStopped {
            callback(value: Void(), handler: event.resultHandler)
            return
        }

        state = .stopping

        ablyService.close { [weak self] result in
            switch result {
            case .success:
                self?.locationService.stopUpdatingLocation()
                self?.enqueue(event: AblyConnectionClosedEvent(resultHandler: event.resultHandler))
            case .failure(let error):
                self?.callback(error: error, handler: event.resultHandler)
            }
        }
    }

    private func performAblyConnectionClosedEvent(_ event: AblyConnectionClosedEvent) {
        state = .stopped
        trackableState.removeAll()
        skippedLocationsState.clearAll()
        callback(value: Void(), handler: event.resultHandler)
    }

    private func performAblyClientConnectionChangedEvent(_ event: AblyClientConnectionStateChangedEvent) {
        receivedAblyClientConnectionState = event.connectionState
        trackables.forEach {
            handleConnectionStateChange(forTrackable: $0)
        }
    }

    private func performAblyChannelConnectionStateChangedEvent(_ event: AblyChannelConnectionStateChangedEvent) {
        receivedAblyChannelsConnectionStates[event.trackable] = event.connectionState
        handleConnectionStateChange(forTrackable: event.trackable)
    }

    private func handleConnectionStateChange(forTrackable trackable: Trackable) {
        var newTrackableState: ConnectionState = .offline
        let channelConnectionState = receivedAblyChannelsConnectionStates[trackable] ?? .offline

        switch receivedAblyClientConnectionState {
        case .online:
            switch channelConnectionState {
            case .online:
                newTrackableState = hasSentAtLeastOneLocation(forTrackable: trackable)
                    ? .online
                    : .offline
            case .offline:
                newTrackableState = .offline
            case .failed:
                newTrackableState = .failed
            }
        case .offline:
            newTrackableState = .offline
        case .failed:
            newTrackableState = .failed
        }

        if newTrackableState != currentTrackablesConnectionStates[trackable] {
            currentTrackablesConnectionStates[trackable] = newTrackableState
            callback(event: DelegateTrackableConnectionStateChangedEvent(trackable: trackable, connectionState: newTrackableState))
        }
    }

    private func hasSentAtLeastOneLocation(forTrackable trackable: Trackable) -> Bool {
        return lastEnhancedLocations[trackable] != nil
    }

    private func performClearRemovedTrackableMetadataEvent(_ event: ClearRemovedTrackableMetadataEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        trackables.remove(event.trackable)
        hooks.trackables?.onTrackableRemoved(trackable: event.trackable)
        removeAllSubscribers(forTrackable: event.trackable)
        resolutions.removeValue(forKey: event.trackable)
        requests.removeValue(forKey: event.trackable)
        lastEnhancedLocations.removeValue(forKey: event.trackable)

        enqueue(event: ClearActiveTrackableEvent(trackable: event.trackable, resultHandler: event.resultHandler))
    }

    private func performClearActiveTrackableEvent(_ event: ClearActiveTrackableEvent) {
        guard !state.isStoppingOrStopped else {
            publisherStoppedCallback(handler: event.resultHandler)
            return
        }

        if activeTrackable == event.trackable {
            activeTrackable = nil
            hooks.trackables?.onActiveTrackableChanged(trackable: nil)
            route = nil
        }

        if trackables.isEmpty {
            locationService.stopUpdatingLocation()
        }

        callback(value: true, handler: event.resultHandler)
    }

    private func removeAllSubscribers(forTrackable trackable: Trackable) {
        guard let trackableSubscribers = subscribers[trackable],
              !trackableSubscribers.isEmpty
        else { return }
        trackableSubscribers.forEach {
            hooks.subscribers?.onSubscriberRemoved(subscriber: $0)
        }
        subscribers[trackable] = []
    }

    // MARK: Location change
    private func performEnhancedLocationChanged(_ event: EnhancedLocationChangedEvent) {
        guard !state.isStoppingOrStopped else {
            logger.error("Cannot perform EnhancedLocationChangedEvent. Publisher is not working.")
            return
        }

        let trackablesToSend = trackables.filter { trackable in
            guard !trackableState.hasPendingMessage(for: trackable.id) else {
                trackableState.addToWaiting(locationUpdate: event.locationUpdate, for: trackable.id)
                return false
            }
            
            let shouldSend = shouldSendLocation(
                location: event.locationUpdate.location,
                lastLocation: lastEnhancedLocations[trackable],
                lastTimestamp: lastEnhancedTimestamps[trackable],
                resolution: resolutions[trackable]
            )
            
            if !shouldSend {
                skippedLocationsState.add(trackableId: trackable.id, location: event.locationUpdate)
            }
            
            return shouldSend
        }

        trackablesToSend.forEach { trackable in
            sendEnhancedLocationUpdate(event: event, trackable: trackable)
        }

        checkThreshold(location: event.locationUpdate.location)
    }
    
    private func processNextWaitingEnhancedLocationUpdate(for trackableId: String) {
        guard let enhancedLocationUpdate = trackableState.nextWaiting(for: trackableId) else {
            return
        }
        
        performEnhancedLocationChanged(EnhancedLocationChangedEvent(locationUpdate: enhancedLocationUpdate))
    }
    
    private func sendEnhancedLocationUpdate(event: EnhancedLocationChangedEvent, trackable: Trackable) {
        lastEnhancedLocations[trackable] = event.locationUpdate.location
        lastEnhancedTimestamps[trackable] = event.locationUpdate.location.timestamp
        
        event.locationUpdate.skippedLocations = skippedLocationsState.list(for: trackable.id).map { $0.location }

        trackableState.markMessageAsPending(for: trackable.id)
        ablyService.sendEnhancedAssetLocationUpdate(locationUpdate: event.locationUpdate, forTrackable: trackable) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.enqueue(event: SendEnhancedLocationFailureEvent(error: error, locationUpdate: event.locationUpdate, trackable: trackable))
            case .success:
                self?.enqueue(event: SendEnhancedLocationSuccessEvent(trackable: trackable, location: event.locationUpdate.location))
            }
        }
    }
    
    private func saveLocationForFurtherSending(trackableId: String, location: EnhancedLocationUpdate) {
        skippedLocationsState.add(trackableId: trackableId, location: location)
    }
    
    private func sendStartTripMetadata(trackable: Trackable) {
        guard let currentLocation = lastEnhancedLocations[trackable] else {
            return
        }
        
        ablyService.sendTripStartMetadata(
            metadata: createTripMetadata(
                trackable: trackable,
                currentLocation: currentLocation
            )
        )
    }
    
    private func sendEndTripMetadata(trackable: Trackable) {
        
    }
    
    private func createTripMetadata(trackable: Trackable, currentLocation: CLLocation) -> TripMetadata {
        TripMetadata(
            trackableId: trackable.id,
            timestamp: Int(Date().timeIntervalSince1970 * 1000),
            originLocation: currentLocation,
            destinationLocation: activeTrackable?.destination?.toCLLocation()
        )
    }
    
    private func performSendEnhancedLocationSuccess(_ event: SendEnhancedLocationSuccessEvent) {
        trackableState.unmarkMessageAsPending(for: event.trackable.id)
        skippedLocationsState.clear(trackableId: event.trackable.id)
        trackableState.resetCounter(for: event.trackable.id)
        processNextWaitingEnhancedLocationUpdate(for: event.trackable.id)
    }
    
    private func performSendEnhancedLocationFailure(_ event: SendEnhancedLocationFailureEvent) {
        guard trackableState.shouldRetry(trackableId: event.trackable.id) else {
            trackableState.unmarkMessageAsPending(for: event.trackable.id)
            saveLocationForFurtherSending(trackableId: event.trackable.id, location: event.locationUpdate)
            callback(event: DelegateErrorEvent(error: event.error))
            processNextWaitingEnhancedLocationUpdate(for: event.trackable.id)
            return
        }
        
        retrySendingEnhancedLocation(
            trackable: event.trackable,
            locationUpdate: event.locationUpdate
        )
    }
    
    private func retrySendingEnhancedLocation(trackable: Trackable, locationUpdate: EnhancedLocationUpdate) {
        trackableState.incrementCounter(for: trackable.id)
        
        sendEnhancedLocationUpdate(
            event: EnhancedLocationChangedEvent(locationUpdate: locationUpdate),
            trackable: trackable
        )
    }

    private func shouldSendLocation(location: CLLocation,
                                    lastLocation: CLLocation?,
                                    lastTimestamp: Date?,
                                    resolution: Resolution?) -> Bool {
        guard let resolution = resolution,
              let lastLocation = lastLocation,
              let lastTimestamp = lastTimestamp
        else { return true }

        let distance = location.distance(from: lastLocation)
        let timeInterval = location.timestamp.timeIntervalSince1970 - lastTimestamp.timeIntervalSince1970

        // desiredInterval in resolution is in milliseconds, while timeInterval from timestamp is in seconds
        let desiredIntervalInSeconds = resolution.desiredInterval / 1000
        return distance >= resolution.minimumDisplacement || timeInterval >= desiredIntervalInSeconds
    }

    // MARK: ResolutionPolicy
    private func performRefreshResolutionPolicyEvent(_ event: RefreshResolutionPolicyEvent) {
        guard !state.isStoppingOrStopped else {
            logger.error("Cannot perform RefreshResolutionPolicyEvent. Publisher is not working.")
            return
        }

        trackables.forEach {
            resolveResolution(trackable: $0)
        }
    }

    private func resolveResolution(trackable: Trackable) {
        let currentRequests = requests[trackable]?.values
        let resolutionSet: Set<Resolution> = currentRequests == nil ? [] : Set(currentRequests!)
        let request = TrackableResolutionRequest(trackable: trackable, remoteRequests: resolutionSet)
        resolutions[trackable] = resolutionPolicy.resolve(request: request)
        enqueue(event: ChangeLocationEngineResolutionEvent())
    }

    private func performChangeLocationEngineResolutionEvent(_ event: ChangeLocationEngineResolutionEvent) {
        locationEngineResolution = resolutionPolicy.resolve(resolutions: Set(resolutions.values))
        changeLocationEngineResolution(resolution: locationEngineResolution)
    }

    private func changeLocationEngineResolution(resolution: Resolution) {
        guard !state.isStoppingOrStopped else {
            logger.error("Cannot perform changeLocationEngineResolution. Publisher is not working.")
            return
        }

        locationService.changeLocationEngineResolution(resolution: resolution)
        enqueue(event: DelegateResolutionUpdateEvent(resolution: resolution))
    }

    private func checkThreshold(location: CLLocation) {
        guard let threshold = proximityThreshold,
              let handler = proximityHandler
        else { return }

        let checker = ThresholdChecker()
        let destination = activeTrackable?.destination != nil ?
            CLLocation(latitude: activeTrackable!.destination!.latitude, longitude: activeTrackable!.destination!.longitude) : nil
        let estimatedArrivalTime = route?.expectedTravelTime == nil ? nil :
            route!.expectedTravelTime + Date().timeIntervalSince1970

        let isReached: Bool = checker.isThresholdReached(threshold: threshold,
                                                         currentLocation: location,
                                                         currentTime: Date().timeIntervalSince1970,
                                                         destination: destination,
                                                         estimatedArrivalTime: estimatedArrivalTime)
        if isReached {
            handler.onProximityReached(threshold: threshold)
        }
    }

    // MARK: Subscribers handling
    private func performPresenceUpdateEvent(_ event: PresenceUpdateEvent) {
        guard !state.isStoppingOrStopped else {
            logger.error("Cannot perform PresenceUpdateEvent. Publisher is not working.")
            return
        }

        guard event.presenceData.type == .subscriber else { return }
        
        if event.presence == .enter {
            addSubscriber(clientId: event.clientId, trackable: event.trackable, data: event.presenceData)
        } else if event.presence == .leave {
            removeSubscriber(clientId: event.clientId, trackable: event.trackable)
        } else if event.presence == .update {
            updateSubscriber(clientId: event.clientId, trackable: event.trackable, data: event.presenceData)
        }
    }

    private func addSubscriber(clientId: String, trackable: Trackable, data: PresenceData) {
        let subscriber = Subscriber(id: clientId, trackable: trackable)
        var trackableSubscribers: Set<Subscriber> = subscribers[trackable] ?? []
        trackableSubscribers.insert(subscriber)
        subscribers[trackable] = trackableSubscribers
        saveOrRemoveResolutionRequest(resolution: data.resolution, trackable: trackable, subscriber: subscriber)
        hooks.subscribers?.onSubscriberAdded(subscriber: subscriber)
        resolveResolution(trackable: trackable)
    }

    private func updateSubscriber(clientId: String, trackable: Trackable, data: PresenceData) {
        guard let trackableSubscribers = subscribers[trackable],
              let subscriber = trackableSubscribers.first(where: { $0.id == clientId })
        else { return }
        saveOrRemoveResolutionRequest(resolution: data.resolution, trackable: trackable, subscriber: subscriber)
        resolveResolution(trackable: trackable)
    }

    private func removeSubscriber(clientId: String, trackable: Trackable) {
        guard var trackableSubscribers = subscribers[trackable],
              let subscriber = trackableSubscribers.first(where: { $0.id == clientId })
        else { return }

        trackableSubscribers.remove(subscriber)
        subscribers[trackable] = trackableSubscribers

        if var trackableRequests = requests[trackable] {
            trackableRequests.removeValue(forKey: subscriber)
            requests[trackable] = trackableRequests
        }

        hooks.subscribers?.onSubscriberRemoved(subscriber: subscriber)
        resolveResolution(trackable: trackable)
    }

    private func saveOrRemoveResolutionRequest(resolution: Resolution?, trackable: Trackable, subscriber: Subscriber) {
        var trackableRequests: [Subscriber: Resolution] = requests[trackable] ?? [:]
        trackableRequests[subscriber] = resolution
        requests[trackable] = trackableRequests
    }

    // MARK: Utils
    private func performOnWorkingThread(_ operation: @escaping () -> Void) {
        workingQueue.async(execute: operation)
    }

    private func performOnMainThread(_ operation: @escaping () -> Void) {
        DispatchQueue.main.async(execute: operation)
    }

    // MARK: Delegate
    private func notifyDelegateDidFailWithError(_ error: ErrorInformation) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.delegate?.publisher(sender: self, didFailWithError: error)
            self.delegateObjectiveC?.publisher(sender: self, didFailWithError: error)
        }
    }

    private func notifyDelegateEnhancedLocationChanged(_ event: DelegateEnhancedLocationChangedEvent) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.delegate?.publisher(sender: self, didUpdateEnhancedLocation: event.locationUpdate.location)
            self.delegateObjectiveC?.publisher(sender: self, didUpdateEnhancedLocation: event.locationUpdate.location)
        }
    }

    private func notifyDelegateConnectionStateChanged(_ event: DelegateTrackableConnectionStateChangedEvent) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.delegate?.publisher(sender: self, didChangeConnectionState: event.connectionState, forTrackable: event.trackable)
            self.delegateObjectiveC?.publisher(sender: self, didChangeConnectionState: event.connectionState)
        }
    }

    private func notifyDelegateResolutionUpdate(_ event: DelegateResolutionUpdateEvent) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.delegate?.publisher(sender: self, didUpdateResolution: event.resolution)
            self.delegateObjectiveC?.publisher(sender: self, didUpdateResolution: event.resolution)
        }
    }
}

// MARK: LocationServiceDelegate
extension DefaultPublisher: LocationServiceDelegate {
    func locationService(sender: LocationService, didFailWithError error: ErrorInformation) {
        logger.error("locationService.didFailWithError. Error: \(error.message)", source: "DefaultPublisher")
        callback(event: DelegateErrorEvent(error: error))
    }

    func locationService(sender: LocationService, didUpdateEnhancedLocationUpdate locationUpdate: EnhancedLocationUpdate) {
        logger.debug("locationService.didUpdateEnhancedLocation.", source: "DefaultPublisher")
        enqueue(event: EnhancedLocationChangedEvent(locationUpdate: locationUpdate))
        callback(event: DelegateEnhancedLocationChangedEvent(locationUpdate: locationUpdate))
    }
}

// MARK: AblyPublisherServiceDelegate
extension DefaultPublisher: AblyPublisherServiceDelegate {
    func publisherService(sender: AblyPublisherService, didChangeChannelConnectionState state: ConnectionState, forTrackable trackable: Trackable) {
        logger.debug("publisherService.didChangeChannelConnectionState. State: \(state) for trackable: \(trackable.id)", source: "DefaultPublisher")
        enqueue(event: AblyChannelConnectionStateChangedEvent(trackable: trackable, connectionState: state))
    }

    func publisherService(sender: AblyPublisherService, didFailWithError error: ErrorInformation) {
        logger.error("publisherService.didFailWithError. Error: \(error.message)", source: "DefaultPublisher")
        callback(event: DelegateErrorEvent(error: error))
    }

    func publisherService(sender: AblyPublisherService, didChangeConnectionState state: ConnectionState) {
        logger.debug("publisherService.didChangeConnectionState. State: \(state)", source: "DefaultPublisher")
        enqueue(event: AblyClientConnectionStateChangedEvent(connectionState: state))
    }

    func publisherService(sender: AblyPublisherService,
                          didReceivePresenceUpdate presence: AblyPresence,
                          forTrackable trackable: Trackable,
                          presenceData: PresenceData,
                          clientId: String) {
        logger.debug("publisherService.didReceivePresenceUpdate. Presence: \(presence), Trackable: \(trackable)",
                     source: "DefaultPublisher")
        enqueue(event: PresenceUpdateEvent(trackable: trackable, presence: presence, presenceData: presenceData, clientId: clientId))
    }
}

// MARK: ResolutionPolicyMethodsDelegate
extension DefaultPublisher: DefaultResolutionPolicyMethodsDelegate {
    func resolutionPolicyMethods(refreshWithSender sender: DefaultResolutionPolicyMethods) {
        enqueue(event: RefreshResolutionPolicyEvent())
    }

    func resolutionPolicyMethods(cancelProximityThresholdWithSender sender: DefaultResolutionPolicyMethods) {
        proximityHandler?.onProximityCancelled()
    }

    func resolutionPolicyMethods(sender: DefaultResolutionPolicyMethods,
                                 setProximityThreshold threshold: Proximity,
                                 withHandler handler: ProximityHandler) {
        self.proximityHandler = handler
        self.proximityThreshold = threshold
    }
}
