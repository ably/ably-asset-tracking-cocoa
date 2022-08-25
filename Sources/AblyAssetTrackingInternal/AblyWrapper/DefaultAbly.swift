import CoreLocation
import Ably
import AblyAssetTrackingCore
import Logging

public class DefaultAbly: AblyCommon {
    
    public weak var publisherDelegate: AblyPublisherDelegate?
    public weak var subscriberDelegate: AblySubscriberDelegate?
    
    private let logger: Logger
    private let client: AblySDKRealtime
    private let connectionConfiguration: ConnectionConfiguration
    let mode: AblyMode
    
    private var channels: [String: AblySDKRealtimeChannel] = [:]

    public required init(factory: AblySDKRealtimeFactory, configuration: ConnectionConfiguration, mode: AblyMode, logger: Logger) {
        self.client = factory.create(withConfiguration: configuration)
        self.mode = mode
        self.logger = logger
        self.connectionConfiguration = configuration
    }
    
    public func connect(
        trackableId: String,
        presenceData: PresenceData,
        useRewind: Bool,
        completion: @escaping ResultHandler<Void>
    ) {
        guard channels[trackableId] == nil else {
            completion(.success)
            
            return
        }
        
        let options = ARTRealtimeChannelOptions()
        options.modes = [.presenceSubscribe, .presence]
        
        if useRewind {
            options.params = ["rewind": "1"]
        }
        
        if mode.contains(.subscribe) {
            options.modes.insert(.subscribe)
        }
        
        if mode.contains(.publish) {
            options.modes.insert(.publish)
        }
        
        let channel = client.channels.getChannelFor(trackingId: trackableId, options: options)
        
        let presenceDataJSON = self.presenceDataJSON(data: presenceData)
                
        channel.presence.enter(presenceDataJSON) { [weak self] error in
            guard let self = self else { return }
            
            let presenceEnterSuccess = { [weak self] in
                guard let self = self else { return }
                
                self.logger.debug("Entered to channel [id: \(trackableId)] presence successfully", source: String(describing: Self.self))
                self.channels[trackableId] = channel
                completion(.success)
            }
            
            let presenceEnterTerminalFailure = { [weak self] (error: ARTErrorInfo) in
                guard let self = self else { return }
                
                self.logger.error("Error during joining to channel [id: \(trackableId)] presence: \(String(describing: error))", source: String(describing: Self.self))
                completion(.failure(error.toErrorInformation()))
            }
            
            guard let error = error else {
                presenceEnterSuccess()
                return
            }
            
            if error.code == ARTErrorCode.operationNotPermittedWithProvidedCapability.rawValue && self.connectionConfiguration.usesTokenAuth {
                self.logger.debug("Failed to enter presence on channel [id: \(trackableId)], requesting Ably SDK to re-authorize", source: String(describing: Self.self))
                self.client.auth.authorize { [weak self] _, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.logger.error("Error calling authorize: \(String(describing: error))", source: String(describing: Self.self))
                        completion(.failure(ErrorInformation(error: error)))
                    } else {
                        self.logger.debug("Authorize succeeded, attaching to channel so that we can retry presence enter", source: String(describing: Self.self))
                        // The channel is currently in the FAILED state, so an immediate attempt to enter presence would fail. We need to first of all explicitly attach to the channel to get it out of the FAILED state (if we _were_ able to attempt to enter presence, doing so would attach to the channel anyway, so we’re not doing anything surprising here).
                        channel.attach { error in
                            if let error = error {
                                self.logger.error("Error attaching to channel [id: \(trackableId)]: \(String(describing: error))", source: String(describing: Self.self))
                                completion(.failure(ErrorInformation(error: error)))
                            } else {
                                self.logger.debug("Channel attach succeeded, retrying presence enter", source: String(describing: Self.self))
                                channel.presence.enter(presenceDataJSON) { error in
                                    guard let error = error else {
                                        presenceEnterSuccess()
                                        return
                                    }
                                    presenceEnterTerminalFailure(error)
                                }
                            }
                        }
                    }
                }
            } else {
                presenceEnterTerminalFailure(error)
            }
        }
    }
    
    public func disconnect(trackableId: String, presenceData: PresenceData, completion: @escaping ResultHandler<Bool>) {
        guard let channelToRemove = channels[trackableId] else {
            completion(.success(false))
            
            return
        }
        
        channelToRemove.presence.leave(presenceDataJSON(data: presenceData)) { [weak self] error in
            guard let error = error else {
                self?.logger.debug("Left channel [id: \(trackableId)] presence successfully", source: String(describing: Self.self))
                
                channelToRemove.presence.unsubscribe()
                channelToRemove.unsubscribe()
                
                channelToRemove.detach { [weak self] detachError in
                    guard let error = detachError else {
                        self?.channels.removeValue(forKey: trackableId)
                        completion(.success(true))
                        
                        return
                    }
                    
                    self?.logger.error("Error during detach channel [id: \(trackableId)] presence: \(String(describing: error))", source: String(describing: Self.self))
                    completion(.failure(error.toErrorInformation()))
                }
                
                return
            }
            
            self?.logger.error("Error during leaving to channel [id: \(trackableId)] presence: \(String(describing: error))", source: String(describing: Self.self))
            completion(.failure(error.toErrorInformation()))
        }
    }
    
    public func close(presenceData: PresenceData, completion: @escaping ResultHandler<Void>) {
        let closingDispatchGroup = DispatchGroup()
        
        for (trackableId, _) in self.channels {
            closingDispatchGroup.enter()
            self.disconnect(trackableId: trackableId, presenceData: presenceData) { result in
                switch result {
                case .success(let wasPresent):
                    self.logger.info("Trackable \(trackableId) removed successfully. Was present \(wasPresent)")
                case .failure(let error):
                    self.logger.error("Removing trackable \(trackableId) failed. Error \(error.message)")
                }
                closingDispatchGroup.leave()
            }
        }
        
        closingDispatchGroup.notify(queue: .main) { [weak self] in
            self?.logger.info("All trackables removed.")
            self?.closeConnection(completion: completion)
        }
    }
    
    public func subscribeForAblyStateChange() {
        client.connection.on { [weak self] stateChange in
            guard let self = self else {
                return
            }
            
            let receivedConnectionState = stateChange.current.toConnectionState()
            
            self.logger.debug("Connection to Ably changed. New state: \(receivedConnectionState.description)", source: String(describing: Self.self))
            self.publisherDelegate?.ablyPublisher(
                sender: self,
                didChangeConnectionState: receivedConnectionState
            )
            self.subscriberDelegate?.ablySubscriber(
                sender: self,
                didChangeClientConnectionState: receivedConnectionState
            )
        }
    }
    
    public func subscribeForPresenceMessages(trackable: Trackable) {
        guard let channel = channels[trackable.id] else {
            return
        }
        
        channel.presence.get { [weak self] messages, error in
            self?.logger.debug("Get presence update from channel", source: String(describing: Self.self))
            guard let self = self, let messages = messages else {
                return
            }
            for message in messages {
                self.handleARTPresenceMessage(message, for: trackable)
            }
        }
        channel.presence.subscribe { [weak self] message in
            self?.logger.debug("Received presence update from channel", source: String(describing: Self.self))
            guard let self = self else { return }
            
            self.handleARTPresenceMessage(message, for: trackable)
        }
    }
    
    private func handleARTPresenceMessage(_ message: ARTPresenceMessage, for trackable: Trackable) {
        guard
            let jsonData = message.data,
            let data: PresenceData = try? PresenceData.fromAny(jsonData),
            let clientId = message.clientId
        else { return }
        
        let presence = Presence(
            action: message.action.toPresenceAction(),
            type: data.type.toPresenceType()
        )
        
        // AblySubscriber delegate
        self.subscriberDelegate?.ablySubscriber(sender: self, didReceivePresenceUpdate: presence)
        self.subscriberDelegate?.ablySubscriber(sender: self, didChangeChannelConnectionState: presence.action.toConnectionState())
        
        // Deleagate `Publisher` resolution if present in PresenceData
        if let resolution = data.resolution, data.type == .publisher {
            self.subscriberDelegate?.ablySubscriber(sender: self, didReceiveResolution: resolution)
        }
        
        // AblyPublisher delegate
        self.publisherDelegate?.ablyPublisher(
            sender: self,
            didReceivePresenceUpdate: presence,
            forTrackable: trackable,
            presenceData: data,
            clientId: clientId
        )
    }
    
    public func subscribeForChannelStateChange(trackable: Trackable) {
        guard let channel = channels[trackable.id] else {
            return
        }
        
        channel.on { [weak self] stateChange in
            guard let self = self else {
                return
            }
            
            let receivedConnectionState = stateChange.current.toConnectionState()
            
            self.logger.debug("Channel state for trackable \(trackable.id) changed. New state: \(receivedConnectionState.description)", source: String(describing: Self.self))
            self.publisherDelegate?.ablyPublisher(sender: self, didChangeChannelConnectionState: receivedConnectionState, forTrackable: trackable)
        }
    }
    
    public func updatePresenceData(trackableId: String, presenceData: PresenceData, completion: ResultHandler<Void>?) {
        guard let channel = channels[trackableId] else {
            return
        }
        
        channel.presence.update(presenceDataJSON(data: presenceData)) { error in
            if let error = error {
                completion?(.failure(error.toErrorInformation()))
            } else {
                completion?(.success)
            }
        }
    }
    
    private func closeConnection(completion: @escaping ResultHandler<Void>) {
        client.connection.on { stateChange in
            switch stateChange.current {
            case .closed:
                self.logger.info("Ably connection closed successfully.")
                completion(.success)
            case .failed:
                let errorInfo = stateChange.reason?.toErrorInformation() ?? ErrorInformation(type: .publisherError(errorMessage: "Cannot close connection"))
                completion(.failure(errorInfo))
            default:
                return
            }
        }
        
        client.close()
    }
}

extension DefaultAbly: AblySubscriber {
    public func subscribeForRawEvents(trackableId: String) {
        guard let channel = channels[trackableId] else {
            return
        }
        
        channel.subscribe(EventName.raw.rawValue) { [weak self] message in
            self?.logger.debug("Received raw location message from channel", source: String(describing: Self.self))
            self?.handleLocationUpdateResponse(forEvent: .raw, messageData: message.data)
        }
    }
    
    public func subscribeForEnhancedEvents(trackableId: String) {
        guard let channel = channels[trackableId] else {
            return
        }
        
        channel.subscribe(EventName.enhanced.rawValue) { [weak self] message in
            self?.logger.debug("Received enhanced location message from channel", source: String(describing: Self.self))
            self?.handleLocationUpdateResponse(forEvent: .enhanced, messageData: message.data)
        }
    }
    
    private func handleLocationUpdateResponse(forEvent event: EventName, messageData: Any?) {
        guard let json = messageData as? String else {
            let errorInformation = ErrorInformation(
                type: .subscriberError(
                    errorMessage: "Cannot parse message data for \(event.rawValue) event: \(String(describing: messageData))"
                )
            )
            subscriberDelegate?.ablySubscriber(sender: self, didFailWithError: errorInformation)
            
            return
        }
        
        do {
            switch event {
            case .raw:
                let message: RawLocationUpdateMessage = try RawLocationUpdateMessage.fromJSONString(json)
                let locationUpdate = RawLocationUpdate(location: message.location.toLocation())
                locationUpdate.skippedLocations = message.skippedLocations.map { $0.toLocation() }
                subscriberDelegate?.ablySubscriber(sender: self, didReceiveRawLocation: locationUpdate)
            case .enhanced:
                let message: EnhancedLocationUpdateMessage = try EnhancedLocationUpdateMessage.fromJSONString(json)
                let locationUpdate = EnhancedLocationUpdate(location: message.location.toLocation())
                locationUpdate.skippedLocations = message.skippedLocations.map { $0.toLocation() }
                subscriberDelegate?.ablySubscriber(sender: self, didReceiveEnhancedLocation: locationUpdate)
            }
        } catch let error {
            guard let errorInformation = error as? ErrorInformation else {
                subscriberDelegate?.ablySubscriber(sender: self, didFailWithError: ErrorInformation(error: error))
                
                return
            }
            
            subscriberDelegate?.ablySubscriber(sender: self, didFailWithError: errorInformation)
            
            return
        }
    }
    
    private func presenceDataJSON(data: PresenceData) -> String {
        do {
            return try data.toJSONString()
        } catch {
            fatalError("Can't encode presenceData. Reason: \(error)")
        }
    }
}

extension DefaultAbly: AblyPublisher {
    public func sendEnhancedLocation(
        locationUpdate: EnhancedLocationUpdate,
        trackable: Trackable,
        completion: ResultHandler<Void>?
    ) {
        
        guard let channel = channels[trackable.id] else {
            let errorInformation = ErrorInformation(type: .publisherError(errorMessage: "Attempt to send location while not tracked channel"))
            completion?(.failure(errorInformation))
            
            return
        }
        
        let message: ARTMessage
        do {
            message = try createARTMessage(for: locationUpdate)
        } catch {
            let errorInformation = ErrorInformation(
                type: .publisherError(errorMessage: "Cannot create location update message. Underlying error: \(error)")
            )
            publisherDelegate?.ablyPublisher(sender: self, didFailWithError: errorInformation)
            
            return
        }
        
        channel.publish([message]) { [weak self] error in
            guard let self = self else {
                return
            }
            
            if let error = error {
                self.publisherDelegate?.ablyPublisher(sender: self, didFailWithError: error.toErrorInformation())
                
                return
            }
            
            self.publisherDelegate?.ablyPublisher(sender: self, didChangeChannelConnectionState: .online, forTrackable: trackable)
            completion?(.success)
        }
    }
    
    public func sendRawLocation(
        location: RawLocationUpdate,
        trackable: Trackable,
        completion: ResultHandler<Void>?
    ) {
        guard let channel = channels[trackable.id] else {
            completion?(.success)
            
            return
        }
        
        do {
            let geoJson = try RawLocationUpdateMessage(locationUpdate: location)
            let data = try geoJson.toJSONString()
            let message = ARTMessage(name: EventName.raw.rawValue, data: data)
            
            channel.publish([message]) { error in
                if let error = error {
                    self.publisherDelegate?.ablyPublisher(sender: self, didFailWithError: error.toErrorInformation())
                } else {
                    completion?(.success)
                }
            }
        } catch {
            let errorInformation = ErrorInformation(
                type: .publisherError(errorMessage: "Cannot create location update message. Underlying error: \(error)")
            )
            publisherDelegate?.ablyPublisher(sender: self, didFailWithError: errorInformation)
        }
    }
    
    private func createARTMessage(for locationUpdate: EnhancedLocationUpdate) throws -> ARTMessage {
        let geoJson = try EnhancedLocationUpdateMessage(locationUpdate: locationUpdate)
        let data = try geoJson.toJSONString()
        
        return ARTMessage(name: EventName.enhanced.rawValue, data: data)
    }
}

fileprivate extension ConnectionConfiguration {
    var usesTokenAuth: Bool {
        return authCallback != nil
    }
}
