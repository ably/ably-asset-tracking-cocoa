import Foundation

public class PublisherWorkerQueueProperties: WorkerQueueProperties
{
    public var isStopped: Bool
    
    public init () {
        isStopped = false
    }
}
