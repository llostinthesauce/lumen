import Foundation
#if os(macOS)
import AppKit
#endif
import CoreGraphics
import UniformTypeIdentifiers
#if canImport(PDFKit)
import PDFKit
#endif

enum AttachmentStorage {
    private static let fileManager = FileManager.default
    
    static func ensureBaseDirectory() {
        let base = AppDirs.attachments
        if !fileManager.fileExists(atPath: base.path) {
            try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        }
    }
    
    #if canImport(UniformTypeIdentifiers)
    static var supportedContentTypes: [UTType] {
        [
            .image,
            .pdf,
            .plainText,
            .utf8PlainText
        ]
    }
    
    static func attachmentType(for url: URL) -> MessageAttachment.AttachmentType? {
        guard let fileType = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return nil
        }
        if fileType.conforms(to: .image) {
            return .image
        }
        if fileType.conforms(to: .pdf)
            || fileType.conforms(to: .plainText)
            || fileType.conforms(to: .utf8PlainText)
            || fileType.conforms(to: .text) {
            return .file
        }
        return nil
    }
    #endif
    
    static func saveAttachment(from sourceURL: URL, type: MessageAttachment.AttachmentType) throws -> MessageAttachment {
        ensureBaseDirectory()
        let attachmentID = UUID()
        let sanitizedName = sanitizeFilename(sourceURL.lastPathComponent)
        let relativeFolder = attachmentID.uuidString
        let destinationFolder = AppDirs.attachments.appendingPathComponent(relativeFolder, isDirectory: true)
        if !fileManager.fileExists(atPath: destinationFolder.path) {
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        
        let destinationURL = destinationFolder.appendingPathComponent(sanitizedName)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }
        if accessed {
            sourceURL.stopAccessingSecurityScopedResource()
        }
        
        let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        
        return MessageAttachment(
            id: attachmentID,
            type: type,
            filename: sanitizedName,
            relativePath: "\(relativeFolder)/\(sanitizedName)",
            fileSize: fileSize,
            contentType: destinationURL.pathExtension.lowercased()
        )
    }
    
    static func removeAttachment(_ attachment: MessageAttachment) {
        let url = url(for: attachment)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url.deletingLastPathComponent())
        }
    }
    
    static func url(for attachment: MessageAttachment) -> URL {
        AppDirs.attachments.appendingPathComponent(attachment.relativePath)
    }
    
    static func removeAll() {
        let base = AppDirs.attachments
        if fileManager.fileExists(atPath: base.path) {
            try? fileManager.removeItem(at: base)
        }
        ensureBaseDirectory()
    }
    
    static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "attachment" : cleaned
    }
    
    static func textContent(for attachment: MessageAttachment, limit: Int = 8000) -> String? {
        guard attachment.type == .file else { return nil }
        let url = attachment.url
        let ext = url.pathExtension.lowercased()
        if ["txt", "md", "markdown", "log", "json", "csv"].contains(ext) {
            if let text = try? String(contentsOf: url) {
                return trimText(text, limit: limit)
            }
            return nil
        } else if ext == "pdf" {
            #if canImport(PDFKit)
            guard let document = PDFDocument(url: url),
                  let text = document.string else {
                return nil
            }
            return trimText(text, limit: limit)
            #else
            return nil
            #endif
        }
        return nil
    }
    
    private static func trimText(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index])
    }
}

public extension MessageAttachment {
    var url: URL {
        AttachmentStorage.url(for: self)
    }
}

extension AttachmentStorage {
    static func saveGeneratedImage(image: CGImage, suggestedName: String) throws -> MessageAttachment {
        ensureBaseDirectory()
        let attachmentID = UUID()
        let sanitizedName = sanitizeFilename(suggestedName)
        let relativeFolder = attachmentID.uuidString
        let destinationFolder = AppDirs.attachments.appendingPathComponent(relativeFolder, isDirectory: true)
        if !fileManager.fileExists(atPath: destinationFolder.path) {
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        let destinationURL = destinationFolder.appendingPathComponent(sanitizedName)
        
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "AttachmentStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create image destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "AttachmentStorage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write generated image"])
        }
        
        let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        
        return MessageAttachment(
            id: attachmentID,
            type: .image,
            filename: sanitizedName,
            relativePath: "\(relativeFolder)/\(sanitizedName)",
            fileSize: fileSize,
            contentType: "png"
        )
    }
}
