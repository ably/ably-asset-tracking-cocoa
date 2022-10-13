//

import SwiftUI
import AblyAssetTrackingPublisher

struct PublisherSettingsView: View {
    @StateObject private var viewModel = PublisherSettingsViewModel()
    @State var showConstantAccuracies = false
    @State var showDefaultAccuracies = false
    @State var showVehicleProfiles = false
    @State var showRoutingProfiles = false
    
    var body: some View {
        List {
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
                TitleValueListItem(title: "Vehicle Profile", value: viewModel.vehicleProfile.description())
                    .onTapGesture {
                        self.showVehicleProfiles = true
                    }
                    .actionSheet(isPresented: $showVehicleProfiles) {
                        var buttons: [Alert.Button] = viewModel.vehicleProfiles.map { profile in
                            Alert.Button.default(Text(profile)) {
                                viewModel.vehicleProfile = VehicleProfile.fromDescription(description: profile)
                            }
                        }
                        buttons.append(.cancel())
                        return ActionSheet(
                            title: Text("Vehicle Profile"),
                            message: Text("Select vehicle profile"),
                            buttons: buttons
                        )
                    }
                TitleValueListItem(title: "Routing profile", value: viewModel.routingProfile.description())
                    .onTapGesture {
                        self.showRoutingProfiles = true
                    }
                    .actionSheet(isPresented: $showRoutingProfiles) {
                        var buttons: [Alert.Button] = viewModel.routingProfiles.map { profile in
                            Alert.Button.default(Text(profile)) {
                                viewModel.routingProfile = RoutingProfile.fromDescription(description: profile)
                            }
                        }
                        buttons.append(.cancel())
                        return ActionSheet(
                            title: Text("Vehicle Profile"),
                            message: Text("Select vehicle profile"),
                            buttons: buttons
                        )
                    }
            } header: {
                Text("Navigation Settings")
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

struct PublisherSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PublisherSettingsView()
    }
}
