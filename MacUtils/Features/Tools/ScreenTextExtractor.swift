import AppKit
import Vision

@MainActor
public final class ScreenTextExtractor {
    public static let shared = ScreenTextExtractor()
    
    private init() {}
    
    public func extractTextFromScreen(completion: (@Sendable (String?) -> Void)? = nil) {
        let tempPath = NSTemporaryDirectory() + "macutils_ocr_\(UUID().uuidString).png"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", tempPath]
            
            do {
                try process.run()
                process.waitUntilExit()
                
                guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: tempPath) else {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }
                
                guard let image = NSImage(contentsOfFile: tempPath),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    DispatchQueue.main.async { completion?(nil) }
                    return
                }
                
                let request = VNRecognizeTextRequest { req, err in
                    try? FileManager.default.removeItem(atPath: tempPath)
                    
                    guard err == nil, let results = req.results as? [VNRecognizedTextObservation] else {
                        DispatchQueue.main.async { completion?(nil) }
                        return
                    }
                    
                    let recognizedStrings = results.compactMap { $0.topCandidates(1).first?.string }
                    let fullText = recognizedStrings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    DispatchQueue.main.async {
                        if !fullText.isEmpty {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(fullText, forType: .string)
                            ClipboardStore.shared.add(fullText)
                            NSSound.beep()
                            completion?(fullText)
                        } else {
                            completion?(nil)
                        }
                    }
                }
                
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
            } catch {
                try? FileManager.default.removeItem(atPath: tempPath)
                DispatchQueue.main.async { completion?(nil) }
            }
        }
    }
}
