import AblyAssetTrackingCore
import AblyAssetTrackingInternal
import QuartzCore

public class DefaultLocationAnimator: NSObject, LocationAnimator {
            
    /**
       Defines how many animation steps have to complete before an event is passed to
       `subscribeForCameraPositionUpdatesClosure`
     */
    public var animationStepsBetweenCameraUpdates: Int = 1
    /**
     * A constant delay added to the animation duration. It helps to smooth out movement
     * when we receive a location update later than we've expected.
     *
     * If you change this value, the new value must be non-negative.
     */
    public var intentionalAnimationDelay: TimeInterval = 2.0 {
        didSet {
            precondition(intentionalAnimationDelay >= 0, "intentionalAnimationDelay must be non-negative")
        }
    }
    
    private var displayLink: CADisplayLink?
    private var subscribeForPositionUpdatesClosure: ((Position) -> Void)?
    private var subscribeForCameraPositionUpdatesClosure: ((Position) -> Void)?
        
    private let logHandler: LogHandler?
    
    private var nextLocationUpdatePrediction: DefaultLocationAnimatorCalculator.Input.Context.NextLocationUpdatePrediction?
    private var state = DefaultLocationAnimatorCalculator.Input.State.initial

    deinit {
        stopAnimationLoop()
    }
    
    public init(logHandler: LogHandler? = nil) {
        self.logHandler = logHandler
        super.init()
        
        startAnimationLoop()
    }
    
    public func stop() {
        stopAnimationLoop()
    }
   
    public func animateLocationUpdate(location: LocationUpdate, expectedIntervalBetweenLocationUpdatesInMilliseconds: Double) {
        let sanitisedExpectedIntervalBetweenLocationUpdatesInMilliseconds: Double
        if expectedIntervalBetweenLocationUpdatesInMilliseconds < 0 {
            logHandler?.warn(message: "Received a negative expectedIntervalBetweenLocationUpdates (\(expectedIntervalBetweenLocationUpdatesInMilliseconds)); clamping to 0", error: nil)
            sanitisedExpectedIntervalBetweenLocationUpdatesInMilliseconds = 0
        } else {
            sanitisedExpectedIntervalBetweenLocationUpdatesInMilliseconds = expectedIntervalBetweenLocationUpdatesInMilliseconds
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.nextLocationUpdatePrediction = .init(receivedAt: CACurrentMediaTime(),
                                                      nextUpdateExpectedIn: sanitisedExpectedIntervalBetweenLocationUpdatesInMilliseconds / 1000)
            self.state.locationsAwaitingAnimation += location.skippedLocations + [location.location]
        }
    }
    
    public func subscribeForPositionUpdates(_ closure: @escaping (Position) -> Void) {
        self.subscribeForPositionUpdatesClosure = closure
    }
    
    public func subscribeForCameraPositionUpdates(_ closure: @escaping (Position) -> Void) {
        self.subscribeForCameraPositionUpdatesClosure = closure
    }
    
    private func startAnimationLoop() {
        let displayLink = CADisplayLink(target: self, selector: #selector(animationLoop))
        displayLink.add(to: .current, forMode: .default)
        
        self.displayLink = displayLink
    }
    
    private func stopAnimationLoop() {
        guard let displayLink = displayLink else {
            return
        }
        
        displayLink.remove(from: .current, forMode: .default)
        displayLink.invalidate()
    }
    
    // Animation loop based on CADisplayLink
    @objc
    private func animationLoop(link: CADisplayLink) {
        let now = CACurrentMediaTime()
        
        let config = DefaultLocationAnimatorCalculator.Input.Config(animationStepsBetweenCameraUpdates: animationStepsBetweenCameraUpdates, intentionalAnimationDelay: intentionalAnimationDelay)
        let context = DefaultLocationAnimatorCalculator.Input.Context(now: now, nextLocationUpdatePrediction: nextLocationUpdatePrediction)
        let input = DefaultLocationAnimatorCalculator.Input(config: config, context: context, state: state)
        let result = DefaultLocationAnimatorCalculator.calculate(input: input)
        
        state = result.newState
        
        // Emit updates to subscribers.
        if let subscriberUpdates = result.subscriberUpdates {
            subscribeForPositionUpdatesClosure?(subscriberUpdates.positionToEmit)
            
            if subscriberUpdates.shouldEmitCameraPositionUpdate {
                subscribeForCameraPositionUpdatesClosure?(subscriberUpdates.positionToEmit)
            }
        }
    }
}

// Models
public extension Location {
    func toPosition() -> Position {
        Position(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accuracy: horizontalAccuracy,
            bearing: course
        )
    }
}
