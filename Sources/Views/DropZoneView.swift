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
                Text("Rechnung ablegen")
                    .font(.title2.weight(.medium))
                Text("PDF oder Bild hierher ziehen, oben in die Toolbar, oder im Finder per Rechtsklick → Dienste → „Zahlungs-QR erzeugen“.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 460)
            }

            Button("Rechnung auswählen …") { model.chooseFile() }
                .controlSize(.large)

            if !settings.hasAPIKey {
                GroupBox {
                    HStack(spacing: 10) {
                        Image(systemName: "key.slash")
                            .foregroundStyle(.orange)
                        Text("Es ist kein OpenAI-API-Key hinterlegt.")
                        SettingsLink { Text("Eintragen") }
                    }
                    .padding(4)
                }
                .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
