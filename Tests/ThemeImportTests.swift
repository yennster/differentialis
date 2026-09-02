import Testing
import Foundation
@testable import Differentialis

@Suite("tmTheme import")
struct TmThemeImportTests {
    /// A Monokai-shaped scheme: explicit markup.inserted/deleted, plus scope colors the
    /// importer must classify by hue (cyan → modified, purple → accent, yellow → conflict).
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0">
    <dict>
      <key>name</key><string>Test Theme</string>
      <key>settings</key>
      <array>
        <dict>
          <key>settings</key>
          <dict>
            <key>background</key><string>#272822</string>
            <key>foreground</key><string>#F8F8F2</string>
            <key>caret</key><string>#F8F8F0</string>
          </dict>
        </dict>
        <dict>
          <key>scope</key><string>markup.inserted</string>
          <key>settings</key><dict><key>foreground</key><string>#A6E22E</string></dict>
        </dict>
        <dict>
          <key>scope</key><string>markup.deleted</string>
          <key>settings</key><dict><key>foreground</key><string>#F92672</string></dict>
        </dict>
        <dict>
          <key>scope</key><string>entity.name.function</string>
          <key>settings</key><dict><key>foreground</key><string>#66D9EF</string></dict>
        </dict>
        <dict>
          <key>scope</key><string>constant.other</string>
          <key>settings</key><dict><key>foreground</key><string>#AE81FF</string></dict>
        </dict>
        <dict>
          <key>scope</key><string>string</string>
          <key>settings</key><dict><key>foreground</key><string>#E6DB74</string></dict>
        </dict>
      </array>
    </dict>
    </plist>
    """

    @Test func mapsScopesAndHues() throws {
        let theme = try TmThemeImporter.colorTheme(from: Data(sample.utf8), fallbackName: "fallback")
        #expect(theme.name == "Test Theme")
        #expect(theme.isDark)
        #expect(theme.isCustom)
        #expect(theme.canvasTop == RGB(hex: "#272822")!.color)
        #expect(theme.added == RGB(hex: "#A6E22E")!.color)      // explicit markup.inserted
        #expect(theme.removed == RGB(hex: "#F92672")!.color)    // explicit markup.deleted
        #expect(theme.modified == RGB(hex: "#66D9EF")!.color)   // hue-matched blue/cyan
        #expect(theme.brand == RGB(hex: "#AE81FF")!.color)      // hue-matched purple
        #expect(theme.conflict == RGB(hex: "#E6DB74")!.color)   // hue-matched yellow/orange
    }

    @Test func detectsLightBackground() throws {
        let light = sample.replacingOccurrences(of: "#272822", with: "#FDF6E3")
        let theme = try TmThemeImporter.colorTheme(from: Data(light.utf8), fallbackName: "fallback")
        #expect(!theme.isDark)
    }

    @Test func usesFallbackNameWhenUnnamed() throws {
        let unnamed = sample.replacingOccurrences(of: "<key>name</key><string>Test Theme</string>", with: "")
        let theme = try TmThemeImporter.colorTheme(from: Data(unnamed.utf8), fallbackName: "Dracula")
        #expect(theme.name == "Dracula")
    }

    @Test func rejectsNonPlistData() {
        #expect(throws: (any Error).self) {
            try TmThemeImporter.colorTheme(from: Data("not a theme".utf8), fallbackName: "x")
        }
    }

    @Test func parsesHexColorForms() {
        #expect(RGB(hex: "#FFF") != nil)
        #expect(RGB(hex: "A6E22E") != nil)
        #expect(RGB(hex: "#A6E22EFF") != nil)
        #expect(RGB(hex: "#GGHHII") == nil)
    }
}

@Suite("Theme settings clamping")
@MainActor
struct ThemeSettingsClampTests {
    /// Regression: these didSets used to self-assign unconditionally, which recurses
    /// through the @Observable accessor until the stack overflows (crash on first
    /// slider drag). Writes — in-range and out-of-range — must settle without recursing.
    @Test func settingsClampWithoutRecursing() {
        let manager = ThemeManager.shared
        let originalFont = manager.codeFontSize
        let originalLight = manager.lightCanvasGradient
        defer {
            manager.codeFontSize = originalFont
            manager.lightCanvasGradient = originalLight
        }

        manager.lightCanvasGradient = 0.5
        #expect(manager.lightCanvasGradient == 0.5)
        manager.lightCanvasGradient = 5
        #expect(manager.lightCanvasGradient == ThemeManager.maxCanvasGradient)
        manager.lightCanvasGradient = -3
        #expect(manager.lightCanvasGradient == 0)

        manager.codeFontSize = 100
        #expect(manager.codeFontSize == ThemeManager.maxFontSize)
        manager.codeFontSize = 1
        #expect(manager.codeFontSize == ThemeManager.minFontSize)
        manager.setFontSize(14)
        #expect(manager.codeFontSize == 14)
    }
}
