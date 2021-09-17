import Foundation

public class Version {
    
    enum ErrorInfo: Error {
        case fileNotFound(String)
        case cantConvertData
    }
    
    private static let fileName = "VERSION"
    
    public static func currentVersion() throws -> String {
        guard let url = Bundle.module.url(forResource: fileName, withExtension: nil) else {
            throw ErrorInfo.fileNotFound(fileName)
        }
        
        let data = try Data(contentsOf: url)
        
        guard let versionString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ErrorInfo.cantConvertData
        }

        return versionString
    }
}
