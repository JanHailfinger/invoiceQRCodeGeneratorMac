import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// EPC-Nutzdaten -> QR-Bild. Fehlerkorrektur M, wie in EPC069-12 empfohlen.
enum QRGenerator {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func image(for payload: String, pixelSize: CGFloat = 1024) -> NSImage? {
        guard !payload.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }

        // Ganzzahlige Skalierung + Nearest Neighbor, damit die Module scharf bleiben.
        let scale = max(1, (pixelSize / output.extent.width).rounded(.down))
        let scaled = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    static func pngData(for payload: String, pixelSize: CGFloat = 1024) -> Data? {
        guard let image = image(for: payload, pixelSize: pixelSize),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
