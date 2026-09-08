import SwiftUI

struct DropZoneView: View {

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Drop an invoice")
                    .font(.title2.weight(.medium))
                Text("Drag a PDF or image here or onto the toolbar, or right-click it in Finder and choose Services, then “Create Payment QR Code”.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 460)
            }

            Button("Choose Invoice…") { model.chooseFile() }
                .controlSize(.large)

            if !settings.hasAPIKey {
                GroupBox {
                    HStack(spacing: 10) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(.orange)
                        Text("No OpenAI API key stored.")
                        SettingsLink { Text("Enter one") }
                    }
                    .padding(4)
                }
                .frame(maxWidth: 440)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
