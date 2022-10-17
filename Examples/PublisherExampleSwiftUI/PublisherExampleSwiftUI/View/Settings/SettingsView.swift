//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State var showConstantAccuracies = false
    @State var showDefaultAccuracies = false
    
    var body: some View {
        List {
            Section {
                TitleValueListItem(title: "Accuracy", value: viewModel.defaultResolutionAccuracy)
                    .onTapGesture {
                        self.showDefaultAccuracies = true
                    }
                    .actionSheet(isPresented: $showDefaultAccuracies) {
                        var buttons: [Alert.Button] = viewModel.accuracies.map { accuracy in
                            Alert.Button.default(Text(accuracy.lowercased())) {
                                viewModel.defaultResolutionAccuracy = accuracy
                            }
                        }
                        buttons.append(.cancel())
                        return ActionSheet(
                            title: Text("Default resolution accuracy"),
                            message: Text("Select accuracy"),
                            buttons: buttons
                        )
                    }
                TitleTextFieldListItem(title: "Desired interval (ms)", value: $viewModel.defaultResolutionDesiredInterval, placeholder: "value", keyboardType: .numberPad)
                TitleTextFieldListItem(title: "Minimum displacement (meters)", value: $viewModel.defaultResolutionMinimumDisplacement, placeholder: "value", keyboardType: .numberPad)
            } header: {
                Text("Default resolution")
            }
            Section {
                TitleValueListItem(title: "Desired Accuracy", value: viewModel.constantResolutionAccuracy)
                    .onTapGesture {
                        self.showConstantAccuracies = true
                    }
                    .disabled(!viewModel.isConstantResolutionEnabled)
                    .actionSheet(isPresented: $showConstantAccuracies) {
                        var buttons: [Alert.Button] = viewModel.accuracies.map { accuracy in
                            Alert.Button.default(Text(accuracy.lowercased())) {
                                viewModel.constantResolutionAccuracy = accuracy
                            }
                        }
                        buttons.append(.cancel())
                        return ActionSheet(
                            title: Text("Desired constant resolution accuracy"),
                            message: Text("Select accuracy"),
                            buttons: buttons
                        )
                    }
                TitleTextFieldListItem(title: "Min Displacement (meters)", value: $viewModel.constantResolutionMinimumDisplacement, placeholder: "value", keyboardType: .numberPad)
                    .disabled(!viewModel.isConstantResolutionEnabled)
            } header: {
                HStack {
                    Text("Constant Resolution")
                    Toggle(isOn: $viewModel.isConstantResolutionEnabled) {}
                }
            }
            
            Section {
                Toggle(isOn: $viewModel.areRawLocationsEnabled) {
                    Text("Raw locations enabled")
                }
                Toggle(isOn: $viewModel.useMapBox) {
                    Text("Use MapBox")
                }
            } header: {
                Text("Other settings")
            }
        }
        .listStyle(.grouped)
        .navigationBarTitle("Settings")
        .resignKeyboardOnTapGesture()
        .onDisappear {
            viewModel.save()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
