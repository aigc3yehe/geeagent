import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
enum BackgroundImageProvider {
    private static let ciContext = CIContext(options: nil)
    private static var originalCache: NSImage?
    private static var pixelatedCache: NSImage?
    private static var originalCustomCache: [String: NSImage] = [:]
    private static var pixelatedCustomCache: [String: NSImage] = [:]

    static func originalBackground(customPath: String? = nil) -> NSImage? {
        if let customPath, !customPath.isEmpty {
            if let cached = originalCustomCache[customPath] {
                return cached
            }

            guard let image = NSImage(contentsOfFile: customPath) else {
                return nil
            }

            originalCustomCache[customPath] = image
            return image
        }

        if let originalCache {
            return originalCache
        }

        guard let path = Bundle.main.path(forResource: "bg", ofType: "png"),
              let image = NSImage(contentsOfFile: path)
        else {
            return nil
        }

        originalCache = image
        return image
    }

    static func pixelatedBackground(customPath: String? = nil) -> NSImage? {
        if let customPath, !customPath.isEmpty {
            if let cached = pixelatedCustomCache[customPath] {
                return cached
            }
        } else if let pixelatedCache {
            return pixelatedCache
        }

        guard
            let path = customPath?.isEmpty == false ? customPath : Bundle.main.path(forResource: "bg", ofType: "png"),
            let input = CIImage(contentsOf: URL(fileURLWithPath: path))
        else {
            return nil
        }

        let filter = CIFilter.pixellate()
        filter.inputImage = input
        filter.scale = 10
        filter.center = CGPoint(x: input.extent.midX, y: input.extent.midY)

        guard
            let output = filter.outputImage?.cropped(to: input.extent),
            let cgImage = ciContext.createCGImage(output, from: input.extent)
        else {
            return nil
        }

        let result = NSImage(cgImage: cgImage, size: NSSize(width: input.extent.width, height: input.extent.height))
        if let customPath, !customPath.isEmpty {
            pixelatedCustomCache[customPath] = result
        } else {
            pixelatedCache = result
        }
        return result
    }
}
