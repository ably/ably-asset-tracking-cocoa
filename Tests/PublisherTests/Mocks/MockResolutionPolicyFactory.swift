import AblyAssetTrackingCore
@testable import AblyAssetTrackingPublisher

class MockResolutionPolicyFactory: ResolutionPolicyFactory {
    var resolutionPolicy: MockResolutionPolicy?
    func createResolutionPolicy(hooks: ResolutionPolicyHooks, methods: ResolutionPolicyMethods) -> ResolutionPolicy {
        if resolutionPolicy == nil {
            resolutionPolicy =  MockResolutionPolicy(hooks: hooks, methods: methods)
        }
        return resolutionPolicy!
    }
}
