import Ably
import CoreLocation
import AblyAssetTrackingCore
import AblyAssetTrackingInternal

class DefaultAblyPublisherService: AblyPublisherService {
    private let client: ARTRealtime
    private let presenceData: PresenceData
    private var channels: [Trackable: ARTRealtimeChannel]

    weak var delegate: AblyPublisherServiceDelegate?

    init(configuration: ConnectionConfiguration) {
        self.client = ARTRealtime(options: configuration.getClientOptions())
        self.presenceData = PresenceData(type: .publisher)
        self.channels = [:]

        setup()
    }

    private func setup() {
        client.connection.on { [weak self] stateChange in
            guard let self = self else {
                return
            }
            
            let receivedConnectionState = stateChange.current.toConnectionState()
            
            logger.debug("Connection to Ably changed. New state: \(receivedConnectionState)", source: "DefaultAblyPublisherService")
            self.delegate?.publisherService(
                sender: self,
                didChangeConnectionState: receivedConnectionState
            )
        }
    }

    // MARK: Main interface
    func track(trackable: Trackable, completion: ResultHandler<Void>?) {
        // Force cast intentional here. It's a fatal error if we are unable to create presenceData JSON
        let data = try! presenceData.toJSONString()

        let channel = client.channels.getChannelFor(trackingId: trackable.id)
        channel.presence.subscribe { [weak self] message in
            guard let self = self,
                  let json = message.data as? String,
                  let data: PresenceData = try? PresenceData.fromJSONString(json),
                  let clientId = message.clientId
            else { return }

            self.delegate?.publisherService(sender: self,
                                            didReceivePresenceUpdate: message.action.toAblyPresence(),
                                            forTrackable: trackable,
                                            presenceData: data,
                                            clientId: clientId)
        }

        channel.presence.enter(data) { error in
            guard let error = error else {
                logger.debug("Entered to presence successfully", source: "AblyPublisherService")
                self.channels[trackable] = channel
                completion?(.success)
                return
            }

            logger.error("Error during joining to channel presence: \(String(describing: error))", source: "AblyPublisherService")
            completion?(.failure(error.toErrorInformation()))
        }

        channel.on { [weak self] stateChange in
            guard let self = self else {
                return
            }
            
            let receivedConnectionState = stateChange.current.toConnectionState()
            
            logger.debug("Channel state for trackable \(trackable.id) changed. New state: \(receivedConnectionState)", source: "DefaultAblyPublisherService")
            self.delegate?.publisherService(sender: self, didChangeChannelConnectionState: receivedConnectionState, forTrackable: trackable)
        }
    }

    func sendEnhancedAssetLocationUpdate(locationUpdate: EnhancedLocationUpdate, forTrackable trackable: Trackable, completion: ResultHandler<Void>?) {
        guard let channel = channels[trackable] else {
            let errorInformation = ErrorInformation(type: .publisherError(errorMessage: "Attempt to send location while not tracked channel"))
            completion?(.failure(errorInformation))
            return
        }

        guard let message = createARTMessage(for: locationUpdate) else {
            let errorInformation = ErrorInformation(type: .publisherError(errorMessage: "Cannot create location update message."))
            self.delegate?.publisherService(sender: self, didFailWithError: errorInformation)
            return
        }

        channel.publish([message]) { [weak self] error in
            guard let self = self else {
                return
            }

            if let error = error {
                self.delegate?.publisherService(sender: self, didFailWithError: error.toErrorInformation())
                return
            }

            self.delegate?.publisherService(sender: self, didChangeChannelConnectionState: .online, forTrackable: trackable)
        }
    }

    private func createARTMessage(for locationUpdate: EnhancedLocationUpdate) -> ARTMessage? {
        do {
            let geoJson = try EnhancedLocationUpdateMessage(locationUpdate: locationUpdate)
            let data = try geoJson.toJSONString()
            return ARTMessage(name: EventName.enhanced.rawValue, data: data)
        } catch let error {
            self.delegate?.publisherService(sender: self, didFailWithError: ErrorInformation(error: error))
            return nil
        }
    }

    func close(completion: @escaping ResultHandler<Void>) {
        closeAllChannels { _ in
            self.closeClientConnection(completion: completion)
        }
    }

    private func closeClientConnection(completion: @escaping ResultHandler<Void>) {
        client.connection.on { connectionChange in
            let connectionState = connectionChange.current

            switch connectionState {
            case .closed:
                logger.info("Ably connection closed successfully.")
                completion(.success)
            case .failed:
                let errorInfo = connectionChange.reason?.toErrorInformation() ?? ErrorInformation(type: .publisherError(errorMessage: "Cannot close connection"))
                completion(.failure(errorInfo))
            default:
                return
            }
        }

        client.close()
    }

    private func closeAllChannels(completion: @escaping ResultHandler<Void>) {
        guard !channels.isEmpty else {
            completion(.success)
            return
        }

        let closingDispatchGroup = DispatchGroup()
        channels.forEach { channel in
            closingDispatchGroup.enter()
            self.stopTracking(trackable: channel.key) { result in
                switch result {
                case .success(let wasPresent):
                    logger.info("Trackable \(channel.key.id) removed successfully. Was present \(wasPresent)")
                    closingDispatchGroup.leave()
                case .failure(let error):
                    logger.error("Removing trackable \(channel.key) failed. Error \(error.message)")
                    closingDispatchGroup.leave()
                }
            }
        }

        closingDispatchGroup.notify(queue: .main) {
            logger.info("All trackables removed.")
            completion(.success)
        }
    }

    func stopTracking(trackable: Trackable, completion: ResultHandler<Bool>?) {
        guard let channel = channels.removeValue(forKey: trackable) else {
            completion?(.success(false))
            return
        }
        // Force cast intentional here. It's a fatal error if we are unable to create presenceData JSON
        let data = try! presenceData.toJSONString()

        channel.presence.unsubscribe()
        channel.presence.leave(data) { error in
            guard let error = error else {
                completion?(.success(true))
                return
            }
            let errorInformation = error.toErrorInformation()
            completion?(.failure(errorInformation))
        }
    }
}
