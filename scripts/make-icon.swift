#!/usr/bin/env swift
//
// MDViewer 앱 아이콘 생성기 — macOS Big Sur 스타일
// 사용: ./scripts/make-icon.swift [preview.png 경로]
//        결과: Sources/MDViewer/Resources/AppIcon.icns
//        preview 경로를 주면 1024 마스터 PNG도 그 위치에 저장한다.
//

import AppKit

let SIZE: CGFloat = 1024
let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = here.deletingLastPathComponent()
let outICNS = root.appendingPathComponent("Sources/MDViewer/Resources/AppIcon.icns")
let previewPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let workDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("MDViewer-iconset-\(UUID().uuidString)")
let iconset = workDir.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// MARK: - 1024 마스터 PNG 그리기

func renderMaster() -> Data {
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
    guard let ctx = NSGraphicsContext.current else { fatalError("no context") }

    // ── 아이콘 본체(squircle) — Big Sur 그리드: 1024 캔버스에 824×824, 여백 100
    let bodyRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyRadius = bodyRect.width * 0.225
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: bodyRadius, yRadius: bodyRadius)

    // 1) 드롭 섀도
    ctx.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.30)
    drop.shadowOffset = NSSize(width: 0, height: -16)
    drop.shadowBlurRadius = 34
    drop.set()
    rgb(0.24, 0.20, 0.66).setFill()
    bodyPath.fill()
    ctx.restoreGraphicsState()

    // 2) 배경 그라디언트 (좌상단 밝은 인디고 → 우하단 딥 인디고)
    ctx.saveGraphicsState()
    bodyPath.addClip()
    NSGradient(colors: [
        rgb(0.46, 0.50, 1.00),
        rgb(0.30, 0.26, 0.85),
        rgb(0.18, 0.12, 0.55)
    ], atLocations: [0.0, 0.55, 1.0], colorSpace: .sRGB)!
        .draw(in: bodyRect, angle: -55)

    // 3) 상단 은은한 광택
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.0)
    ])!.draw(in: NSRect(x: bodyRect.minX, y: bodyRect.midY + bodyRect.height * 0.12,
                        width: bodyRect.width, height: bodyRect.height * 0.38),
             angle: -90)

    // ── 4) 문서 카드 (흰색, 우상단 접힌 귀퉁이)
    let card = NSRect(x: 288, y: 218, width: 448, height: 588)
    let cardRadius: CGFloat = 40
    let ear: CGFloat = 104   // 접힌 귀퉁이 크기

    // 카드 외곽선(dog-ear 반영): 시계 방향, 우상단 모서리는 잘라낸다.
    let cardPath = NSBezierPath()
    cardPath.move(to: NSPoint(x: card.minX + cardRadius, y: card.maxY))
    cardPath.line(to: NSPoint(x: card.maxX - ear, y: card.maxY))
    cardPath.line(to: NSPoint(x: card.maxX, y: card.maxY - ear))
    cardPath.line(to: NSPoint(x: card.maxX, y: card.minY + cardRadius))
    cardPath.appendArc(withCenter: NSPoint(x: card.maxX - cardRadius, y: card.minY + cardRadius),
                       radius: cardRadius, startAngle: 0, endAngle: -90, clockwise: true)
    cardPath.line(to: NSPoint(x: card.minX + cardRadius, y: card.minY))
    cardPath.appendArc(withCenter: NSPoint(x: card.minX + cardRadius, y: card.minY + cardRadius),
                       radius: cardRadius, startAngle: -90, endAngle: -180, clockwise: true)
    cardPath.line(to: NSPoint(x: card.minX, y: card.maxY - cardRadius))
    cardPath.appendArc(withCenter: NSPoint(x: card.minX + cardRadius, y: card.maxY - cardRadius),
                       radius: cardRadius, startAngle: 180, endAngle: 90, clockwise: true)
    cardPath.close()

    ctx.saveGraphicsState()
    let cardShadow = NSShadow()
    cardShadow.shadowColor = rgb(0.06, 0.03, 0.30, 0.45)
    cardShadow.shadowOffset = NSSize(width: 0, height: -10)
    cardShadow.shadowBlurRadius = 26
    cardShadow.set()
    rgb(0.99, 0.99, 1.00).setFill()
    cardPath.fill()
    ctx.restoreGraphicsState()

    // 접힌 귀퉁이(살짝 어두운 삼각형 + 미세 그림자)
    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: card.maxX - ear, y: card.maxY))
    fold.line(to: NSPoint(x: card.maxX - ear, y: card.maxY - ear))
    fold.line(to: NSPoint(x: card.maxX, y: card.maxY - ear))
    fold.close()
    ctx.saveGraphicsState()
    let foldShadow = NSShadow()
    foldShadow.shadowColor = rgb(0.10, 0.08, 0.35, 0.35)
    foldShadow.shadowOffset = NSSize(width: -4, height: -6)
    foldShadow.shadowBlurRadius = 12
    foldShadow.set()
    NSGradient(colors: [rgb(0.86, 0.87, 0.97), rgb(0.74, 0.76, 0.92)])!
        .draw(in: fold, angle: -45)
    ctx.restoreGraphicsState()

    // ── 5) 카드 콘텐츠
    let inset: CGFloat = 52
    let contentX = card.minX + inset
    let contentW = card.width - inset * 2

    // 5-1) "M↓" 마크 (카드 상단) — 마크다운 정체성
    let markFont = NSFont.systemFont(ofSize: 128, weight: .heavy)
    let markStr = NSAttributedString(string: "M↓", attributes: [
        .font: markFont,
        .foregroundColor: rgb(0.30, 0.27, 0.86),
        .kern: -4
    ])
    let markSize = markStr.size()
    markStr.draw(at: NSPoint(x: contentX - 4, y: card.maxY - inset - markSize.height + 10))

    // 5-2) 본문 줄 (연회색 라운드 바)
    let lineColor = rgb(0.84, 0.85, 0.91)
    let lineH: CGFloat = 26
    let lineGap: CGFloat = 52
    var lineY = card.maxY - inset - markSize.height - 44
    for w in [1.0, 0.78, 0.60] as [CGFloat] {
        lineColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: contentX, y: lineY, width: contentW * w, height: lineH),
                     xRadius: lineH / 2, yRadius: lineH / 2).fill()
        lineY -= lineGap
    }

    // 5-3) JSON 코드블록 (다크 네이비 카드 + 중괄호 + 토큰 바)
    let block = NSRect(x: contentX, y: card.minY + 44, width: contentW, height: lineY - card.minY - 20)
    rgb(0.13, 0.13, 0.24).setFill()
    NSBezierPath(roundedRect: block, xRadius: 24, yRadius: 24).fill()

    let braceFont = NSFont.monospacedSystemFont(ofSize: 92, weight: .bold)
    let braceColor = rgb(1.00, 0.78, 0.35)
    let lBrace = NSAttributedString(string: "{", attributes: [.font: braceFont, .foregroundColor: braceColor])
    let rBrace = NSAttributedString(string: "}", attributes: [.font: braceFont, .foregroundColor: braceColor])
    let braceY = block.midY - lBrace.size().height / 2
    lBrace.draw(at: NSPoint(x: block.minX + 26, y: braceY))
    rBrace.draw(at: NSPoint(x: block.maxX - 26 - rBrace.size().width, y: braceY))

    // 코드 토큰 바 (키: 하늘 / 문자열: 그린 / 숫자: 퍼플)
    let tokenH: CGFloat = 22
    let tokenX = block.minX + 26 + lBrace.size().width + 26
    let tokenMaxW = block.maxX - 26 - rBrace.size().width - 26 - tokenX
    let tokens: [(CGFloat, CGFloat, NSColor)] = [   // (x offset 비율, 폭 비율, 색)
        (0.00, 0.42, rgb(0.45, 0.72, 1.00)),
        (0.50, 0.48, rgb(0.48, 0.86, 0.55)),
        (0.00, 0.34, rgb(0.45, 0.72, 1.00)),
        (0.42, 0.30, rgb(0.80, 0.63, 1.00))
    ]
    var tokenY = block.midY + 34
    for (i, t) in tokens.enumerated() {
        t.2.setFill()
        NSBezierPath(roundedRect: NSRect(x: tokenX + tokenMaxW * t.0, y: tokenY,
                                         width: tokenMaxW * t.1, height: tokenH),
                     xRadius: tokenH / 2, yRadius: tokenH / 2).fill()
        if i % 2 == 1 { tokenY -= 44 }
    }

    ctx.restoreGraphicsState()   // body clip 해제
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])!
}

let masterPNG = renderMaster()

if let previewPath {
    try? masterPNG.write(to: URL(fileURLWithPath: previewPath))
    print("Preview: \(previewPath)")
}

// MARK: - 크기별 PNG 작성

func resize(_ src: Data, to size: Int) -> Data {
    // lockFocus는 디스플레이 배율을 타서 Retina에서 2배 픽셀 PNG가 나온다 —
    // iconutil이 슬롯 크기 불일치로 해당 크기를 누락시키므로, 픽셀 크기를
    // 고정한 NSBitmapImageRep에 직접 그린다.
    let img = NSImage(data: src)!
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
             from: NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height),
             operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
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
