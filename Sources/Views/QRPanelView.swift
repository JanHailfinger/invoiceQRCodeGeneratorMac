import SwiftUI

struct QRPanelView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        let payload = model.payload

        VStack(spacing: 14) {
            qrCode(payload)

            if payload.isUsable {
                Text("Mit der Banking-App scannen")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !payload.issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(payload.issues) { issue in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: issue.isBlocking ? "xmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(issue.isBlocking ? .red : .secondary)
                            Text(issue.text)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            HStack {
                Text("\(payload.byteCount) / \(EPCPayload.maximumByteCount) Byte")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    Button("QR-Bild kopieren") { model.copyQRImage() }
                    Button("Nutzdaten kopieren") { model.copyPayload() }
                    Button("Als PNG speichern …") { model.saveQRImage() }
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!payload.isUsable)
            }

            DisclosureGroup("Nutzdaten (EPC069-12)") {
                Text(payload.text.isEmpty ? "—" : payload.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            .font(.caption)
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func qrCode(_ payload: EPCPayload) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .shadow(radius: 1, y: 1)

            if payload.isUsable, let image = QRGenerator.image(for: payload.text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
                    .accessibilityLabel("SEPA-Zahlungs-QR-Code")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 40, weight: .ultraLight))
                    Text("Pflichtfelder ergänzen")
                        .font(.caption)
                }
                .foregroundStyle(.gray)
            }
        }
        .frame(width: 280, height: 280)
    }
}
