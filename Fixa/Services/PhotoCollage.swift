import UIKit

/// Combines up to three photos into one JPEG for the e-service, which accepts a single file.
/// Each photo is fitted whole into its cell (letterboxed on paper), so nothing in it is cropped away.
/// Re-rendering drops all EXIF/GPS metadata from the originals.
enum PhotoCollage {
    static let maxBytes = 2_000_000
    private static let canvasLongEdge: CGFloat = 2000
    private static let gutter: CGFloat = 8

    static func combine(_ images: [UIImage], maxBytes: Int = maxBytes) -> Data? {
        let photos = Array(images.prefix(3))
        guard !photos.isEmpty else { return nil }
        var edge = canvasLongEdge
        while edge >= 600 {
            let image = render(photos, longEdge: edge)
            var quality: CGFloat = 0.85
            while quality >= 0.35 {
                if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                    return data
                }
                quality -= 0.1
            }
            edge *= 0.75
        }
        return render(photos, longEdge: 600).jpegData(compressionQuality: 0.3)
    }

    /// Small thumbnail for history rows.
    static func thumbnail(from jpeg: Data, side: CGFloat = 160) -> Data? {
        guard let image = UIImage(data: jpeg) else { return nil }
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let thumb = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(image, aspectFillIn: CGRect(origin: .zero, size: size))
        }
        return thumb.jpegData(compressionQuality: 0.7)
    }

    private static func render(_ photos: [UIImage], longEdge: CGFloat) -> UIImage {
        let size: CGSize
        let rects: [CGRect]
        switch photos.count {
        case 1:
            let p = photos[0].size
            let scale = longEdge / max(p.width, p.height, 1)
            size = CGSize(width: (p.width * scale).rounded(), height: (p.height * scale).rounded())
            rects = [CGRect(origin: .zero, size: size)]
        case 2:
            size = CGSize(width: longEdge, height: (longEdge * 0.75).rounded())
            let w = (size.width - gutter) / 2
            rects = [
                CGRect(x: 0, y: 0, width: w, height: size.height),
                CGRect(x: w + gutter, y: 0, width: w, height: size.height),
            ]
        default:
            size = CGSize(width: longEdge, height: (longEdge * 0.75).rounded())
            let bigW = ((size.width - gutter) * 0.6).rounded()
            let smallW = size.width - gutter - bigW
            let smallH = (size.height - gutter) / 2
            rects = [
                CGRect(x: 0, y: 0, width: bigW, height: size.height),
                CGRect(x: bigW + gutter, y: 0, width: smallW, height: smallH),
                CGRect(x: bigW + gutter, y: smallH + gutter, width: smallW, height: smallH),
            ]
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (photo, rect) in zip(photos, rects) {
                paper.setFill()
                context.fill(rect)
                draw(photo, aspectFitIn: rect)
            }
        }
    }

    /// Warm off-white behind a fitted photo (the app's light paper colour).
    private static let paper = UIColor(red: 0xF7 / 255, green: 0xF5 / 255, blue: 0xF0 / 255, alpha: 1)

    private static func draw(_ image: UIImage, aspectFitIn rect: CGRect) {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = min(rect.width / s.width, rect.height / s.height)
        let w = s.width * scale
        let h = s.height * scale
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }

    private static func draw(_ image: UIImage, aspectFillIn rect: CGRect) {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = max(rect.width / s.width, rect.height / s.height)
        let w = s.width * scale
        let h = s.height * scale
        image.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    }
}
