import AppKit
import Foundation
import Vision

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ocr_screenshot.swift IMAGE [x y w h]\n".utf8))
    exit(1)
}

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      var cgImage = rep.cgImage
else {
    FileHandle.standardError.write(Data("unable to load \(path)\n".utf8))
    exit(1)
}

if CommandLine.arguments.count >= 6,
   let x = Int(CommandLine.arguments[2]),
   let y = Int(CommandLine.arguments[3]),
   let w = Int(CommandLine.arguments[4]),
   let h = Int(CommandLine.arguments[5]),
   w > 8,
   h > 8
{
    let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
    let crop = CGRect(x: x, y: y, width: w, height: h).intersection(bounds)
    if crop.width > 8, crop.height > 8, let cut = cgImage.cropping(to: crop) {
        cgImage = cut
    }
}

if cgImage.width < 900 || cgImage.height < 900 {
    let scale: CGFloat = 2
    let size = CGSize(width: CGFloat(cgImage.width) * scale, height: CGFloat(cgImage.height) * scale)
    let scaled = NSImage(size: size)
    scaled.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: cgImage, size: .zero).draw(
        in: CGRect(origin: .zero, size: size),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    scaled.unlockFocus()
    if let scaledTiff = scaled.tiffRepresentation,
       let scaledRep = NSBitmapImageRep(data: scaledTiff),
       let scaledCG = scaledRep.cgImage
    {
        cgImage = scaledCG
    }
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = false

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    FileHandle.standardError.write(Data("ocr failed: \(error)\n".utf8))
    exit(1)
}

let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
print(lines.joined(separator: "\n"))
