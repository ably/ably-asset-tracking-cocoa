import Foundation

/// A worker that runs tasks that the Publisher and Subscriber used to run asynchronously on their
/// own dispatch queues. This worker allows us to tie up legacy work and new asynchronous
/// work, for simplicity and consistency during the transition.
open class LegacyWorker<PropertiesType, WorkerSpecificationType> : Worker
{
    let work: () -> Void
    let logger: InternalLogHandler?

    public init (work: @escaping () -> Void, logger: InternalLogHandler?) {
        self.work = work
        self.logger = logger
    }

    public func doWork(properties: PropertiesType, doAsyncWork: (@escaping ((Error?) -> Void) -> Void) -> Void, postWork: @escaping (WorkerSpecificationType) -> Void) throws -> PropertiesType {
        logger?.debug(message: "Queueing up legacy asynchronous work", error: nil)
        doAsyncWork({ [logger, work] _ in
            logger?.debug(message: "Executing legacy asynchronous work", error: nil)
            work()
        })

        return properties
    }

    public func doWhenStopped(error: Error) {
        //TODO
    }

    public func onUnexpectedError(error: Error, postWork: @escaping (WorkerSpecificationType) -> Void) {
        //TODO
    }

    public func onUnexpectedAsyncError(error: Error, postWork: @escaping (WorkerSpecificationType) -> Void) {
        //TODO
    }
}
