import XCTest
@testable import AblyAssetTrackingCore

class VersionTest: XCTestCase {
    func testCurrentVersionIsSetAndSemantic() {
        let pattern = "^\\d+.\\d+.\\d+(-||)(alpha||beta||gamma||alpha.\\d+||beta.\\d+||gamma.\\d+||alpha.beta)$"
        do {
            let version = try AblyAssetTrackingCore.Version.currentVersion()
            let range = NSRange(location: .zero, length: version.utf8.count)
            let expression = try NSRegularExpression(pattern: pattern)
            
            if expression.firstMatch(in: version, options: [], range: range) == nil {
                XCTFail("Wrong Sematic Version: \(version)")
            }
        } catch {
            XCTFail("\(error)")
        }
    }
}
