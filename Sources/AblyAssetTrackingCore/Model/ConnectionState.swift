import Foundation

/**
 Indicates Asset connection status (i.e. if courier is publishing their location)
 */
public enum ConnectionState: Int {
    /**
     Asset is connected to tracking system and we're receiving their position
     */
    case online

    /**
     Asset is not connected
     */
    case offline
    
    /**
     Connection has failed
     */
    case failed
}

extension ConnectionState {
    var string: String {
        get {
            switch self {
            case .online:
                return "online"
            case .offline:
                return "offline"
            case .failed:
                return "failed"
            }
        }
    }
    public var description: String {
        "ConnectionState.\(string)"
    }
}
