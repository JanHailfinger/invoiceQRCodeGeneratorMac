import SwiftUI

struct QRPanelView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        let payload = model.payload

        VStack(spacing: 14) {
            qrCode(payload)

            if payload.isUsable {
                Text("Scan with your banking app")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !payload.issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(payload.issues) { issue in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: issue.isBlocking ? "xmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(issue.isBlocking ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
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
                Text("\(payload.byteCount) / \(EPCPayload.maximumByteCount) bytes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    Button("Copy QR Image") { model.copyQRImage() }
                    Button("Copy Payload") { model.copyPayload() }
                    Button("Save as PNG…") { model.saveQRImage() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!payload.isUsable)
            }

            DisclosureGroup("Payload (EPC069-12)") {
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
                    .accessibilityLabel("SEPA payment QR code")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 40, weight: .ultraLight))
                    Text("Fill in the required fields")
                        .font(.caption)
                }
                .foregroundStyle(.gray)
            }
        }
        .frame(width: 280, height: 280)
    }
}
