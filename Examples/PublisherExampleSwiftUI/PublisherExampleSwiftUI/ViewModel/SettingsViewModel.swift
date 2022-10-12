//

import Foundation
import SwiftUI
import AblyAssetTrackingPublisher

class SettingsViewModel: ObservableObject {
    @Published var areRawLocationsEnabled: Bool = SettingsModel.shared.areRawLocationsEnabled {
        didSet {
            SettingsModel.shared.areRawLocationsEnabled = areRawLocationsEnabled
        }
    }
    
    @Published var isConstantResolutionEnabled: Bool = SettingsModel.shared.isConstantResolutionEnabled {
        didSet {
            SettingsModel.shared.isConstantResolutionEnabled = isConstantResolutionEnabled
        }
    }
    
    @Published var constantResolutionMinimumDisplacement: String  = "\(SettingsModel.shared.constantResolution.minimumDisplacement)"
    @Published var defaultResolutionMinimumDisplacement: String  = "\(SettingsModel.shared.defaultResolution.minimumDisplacement)"
    @Published var defaultResolutionDesiredInterval: String  = "\(SettingsModel.shared.defaultResolution.desiredInterval)"
    
    var constantResolutionAccuracy: String = SettingsModel.shared.constantResolution.accuracy.rawValue
    var defaultResolutionAccuracy: String = SettingsModel.shared.defaultResolution.accuracy.rawValue
    var accuracies: [String] {
        [Accuracy.low.rawValue,
         Accuracy.high.rawValue,
         Accuracy.balanced.rawValue,
         Accuracy.maximum.rawValue,
         Accuracy.minimum.rawValue].sorted()
    }
    
    func save() {
        if let constantAccuracy = Accuracy(rawValue: constantResolutionAccuracy),
           let constantDisplacement = Double(constantResolutionMinimumDisplacement) {
            SettingsModel.shared.constantResolution = .init(accuracy: constantAccuracy,
                                                            desiredInterval: .zero,
                                                            minimumDisplacement: constantDisplacement)
        }
        
        if let defaultAccuracy = Accuracy(rawValue: defaultResolutionAccuracy),
        let defaultDisplacement = Double(defaultResolutionMinimumDisplacement),
        let defaultDesiredInterval = Double(defaultResolutionDesiredInterval) {
            SettingsModel.shared.defaultResolution = .init(accuracy: defaultAccuracy,
                                                           desiredInterval: defaultDesiredInterval,
                                                           minimumDisplacement: defaultDisplacement)
        }
    }
}
