import Foundation

public enum AuthResult {
    case jwt(String)
    case tokenRequest(TokenRequest)
    case tokenDetails(TokenDetails)
}

public typealias Token = String
public typealias AuthCallback = (TokenParams, @escaping (Result<AuthResult, Error>) -> Void) -> Void

public class ConnectionConfiguration: NSObject {
    public let apiKey: String?
    public let clientId: String?
    public let authCallback: AuthCallback?

    /**
     Connect to Ably using basic authentication (API Key)
     - Parameters:
       - apiKey: API key string obtained from application dashboard.
       - clientId: Optional identifier to be assigned to this client.
         - authCallback:
     */
    private init(apiKey: String?,
                clientId: String?,
                authCallback: AuthCallback?) {
        self.apiKey = apiKey
        self.clientId = clientId
        self.authCallback = authCallback
    }

    // TODO make clientId optional [RSA7b2], and use the clientId provided in the auth callback. Pending ably-cocoa: https://github.com/ably/ably-cocoa/issues/1126
    /**
     Connect to Ably with authCallback authentication, where the authCallback is passed a [TokenRequest]

     - Parameters:
       - authCallbackExpectingTokenRequest: A closure which generates a token request, token details or token string when
        given token parameters.
       - clientId: Optional identifier to be assigned to this client.
     */
    public convenience init(clientId: String? = nil, authCallback: @escaping AuthCallback) {
        self.init(apiKey: nil,
                  clientId: clientId,
                  authCallback: authCallback)
    }

    public convenience init(apiKey: String, clientId: String? = nil) {
        self.init(apiKey: apiKey,
                  clientId: clientId,
                  authCallback: nil)
    }
}
