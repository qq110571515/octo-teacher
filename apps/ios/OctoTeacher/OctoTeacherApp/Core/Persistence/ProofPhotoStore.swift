import Foundation
import UIKit

/// 任务证明照片的本机存储。
///
/// 隐私边界：照片只写入 App 沙盒 Documents/proof-photos，绝不上传网络、
/// 不写系统相册、不对亲友展示原图。删除任务或重新提交时旧照片会被清理。
/// 实例只持有不可变目录路径，文件操作交给 FileManager，可安全跨并发域使用。
final class ProofPhotoStore: Sendable {
    static let shared = ProofPhotoStore()

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = documents.appendingPathComponent("proof-photos", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// 压缩并保存一张证明照片，返回文件名；失败返回 nil。
    /// 最长边压到 1600pt、JPEG 0.7，家庭测试足够清晰且不吃存储。
    func save(imageData: Data) -> String? {
        guard let image = UIImage(data: imageData) else { return nil }
        guard let jpegData = Self.downscaledJPEGData(from: image) else { return nil }

        let fileName = "proof-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try jpegData.write(to: url, options: [.atomic])
            return fileName
        } catch {
            return nil
        }
    }

    /// 读取一张已保存的证明照片。
    func loadImage(fileName: String) -> UIImage? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 删除一张证明照片（重新提交或删除任务时调用）。
    func delete(fileName: String) {
        let url = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    private static func downscaledJPEGData(from image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else {
            return image.jpegData(compressionQuality: 0.7)
        }

        let scale = maxDimension / largest
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
