import XCTest
@testable import MCPDictIOS

final class Version0105ReleaseTests: XCTestCase {
    func testAndroidExportRoundTrip() throws {
        var original = CustomLanguageSchemes()
        original.schemes = [.init(name: "方案", languages: [], colorHex: "#123456"),
                            .init(name: "方案－南", languages: ["甲", "乙 & 丙"], colorHex: "#234567", languageColors: ["甲": "#FF0000"]),
                            .init(name: "方案－南－空", languages: [], colorHex: "#ABCDEF")]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("方案.xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try AndroidSchemeWorkbook.write(original, root: "方案").write(to: url)
        XCTAssertEqual(try AndroidSchemeWorkbook.read(url).schemes, original.schemes)
    }
    func testToneAndSilence() throws {
        let pcm: [Float] = (0..<16000).map { Float(sin(Double($0)*2 * .pi*200/16000))*0.2 }
        let tone = try SpeechClip.analyze(pcm)
        let last = try XCTUnwrap(tone.frames.last)
        XCTAssertEqual(tone.duration, 1)
        XCTAssertEqual(last.pitch, 200, accuracy: 2)
        XCTAssertEqual(last.intensity, 77, accuracy: 2)
        XCTAssertGreaterThan(tone.frames.flatMap(\.pulses).count, 150)
        XCTAssertEqual(tone.spectrum.width, 250)
        let silence = try SpeechClip.analyze(Array(repeating: 0,count: 2048))
        XCTAssertTrue(silence.frames.allSatisfy { $0.pitch.isNaN && $0.pulses.isEmpty && $0.formants.isEmpty })
    }
}
