#!/usr/bin/env swift
//
// MDViewer 앱 아이콘 생성기
// 사용: ./scripts/make-icon.swift
//        결과: Sources/MDViewer/Resources/AppIcon.icns
//

import AppKit

let SIZE: CGFloat = 1024
let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = here.deletingLastPathComponent()
let outICNS = root.appendingPathComponent("Sources/MDViewer/Resources/AppIcon.icns")
let workDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("MDViewer-iconset-\(UUID().uuidString)")
let iconset = workDir.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// MARK: - 1024 마스터 PNG 그리기

func renderMaster() -> Data {
    let rect = NSRect(x: 0, y: 0, width: SIZE, height: SIZE)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(SIZE), pixelsHigh: Int(SIZE),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // 1) 둥근 사각형 (macOS squircle 근사)
    let cornerRadius = SIZE * 0.2237
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgPath.addClip()

    // 2) 그라디언트 배경 (위→아래)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.18, green: 0.42, blue: 0.86, alpha: 1.0),   // 상단: 푸른빛
        NSColor(srgbRed: 0.09, green: 0.20, blue: 0.55, alpha: 1.0)    // 하단: 깊은 남청
    ])!
    gradient.draw(in: rect, angle: -90)

    // 3) 살짝 광택 (상단 highlight)
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.18),
        NSColor.white.withAlphaComponent(0.0)
    ])!
    let highlightRect = NSRect(x: 0, y: SIZE * 0.5, width: SIZE, height: SIZE * 0.5)
    highlight.draw(in: highlightRect, angle: -90)

    // 4) "문서 카드" 모티프 — 흰 사각형
    let cardInset = SIZE * 0.16
    let cardRect = NSRect(x: cardInset,
                          y: cardInset * 0.85,
                          width: SIZE - cardInset * 2,
                          height: SIZE - cardInset * 1.7)
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: SIZE * 0.05, yRadius: SIZE * 0.05)
    NSColor.white.withAlphaComponent(0.95).setFill()
    cardPath.fill()

    // 4-1) 카드 위 텍스트 줄들 (마크다운 라인 느낌)
    let lineColor = NSColor(srgbRed: 0.78, green: 0.84, blue: 0.92, alpha: 1)
    lineColor.setFill()
    let lineX = cardRect.minX + cardRect.width * 0.10
    let lineW = cardRect.width * 0.80
    let lineH = SIZE * 0.030
    let baseY = cardRect.maxY - SIZE * 0.18
    let gap = SIZE * 0.058
    let widths: [CGFloat] = [1.0, 0.85, 0.62, 0.92, 0.55]
    for (i, w) in widths.enumerated() {
        let y = baseY - CGFloat(i) * gap
        let r = NSRect(x: lineX, y: y, width: lineW * w, height: lineH)
        NSBezierPath(roundedRect: r, xRadius: lineH/2, yRadius: lineH/2).fill()
    }

    // 5) 중앙 "M↓" 큰 마크 (브랜드)
    let markFont = NSFont.systemFont(ofSize: SIZE * 0.30, weight: .black)
    let mark = "M↓"
    let markAttrs: [NSAttributedString.Key: Any] = [
        .font: markFont,
        .foregroundColor: NSColor(srgbRed: 0.10, green: 0.22, blue: 0.55, alpha: 1.0),
        .kern: -SIZE * 0.015
    ]
    let markStr = NSAttributedString(string: mark, attributes: markAttrs)
    let markSize = markStr.size()
    let markRect = NSRect(
        x: (SIZE - markSize.width) / 2,
        y: cardRect.minY + cardRect.height * 0.12,
        width: markSize.width,
        height: markSize.height
    )
    markStr.draw(in: markRect)

    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])!
}

let masterPNG = renderMaster()

// MARK: - 크기별 PNG 작성

func resize(_ src: Data, to size: Int) -> Data {
    let img = NSImage(data: src)!
    let target = NSImage(size: NSSize(width: size, height: size))
    target.lockFocus()
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
             from: NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height),
             operation: .copy, fraction: 1.0)
    target.unlockFocus()
    let tiff = target.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: .png, properties: [:])!
}

let outputs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]
for o in outputs {
    let data = o.size == 1024 ? masterPNG : resize(masterPNG, to: o.size)
    try data.write(to: iconset.appendingPathComponent(o.name))
}

// MARK: - iconutil로 .icns 빌드

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", outICNS.path, iconset.path]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("Wrote \(outICNS.path)")
} else {
    print("iconutil failed (\(task.terminationStatus))")
    exit(1)
}

// 정리
try? FileManager.default.removeItem(at: workDir)
