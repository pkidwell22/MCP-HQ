import XCTest

final class PackageAppScriptTests: XCTestCase {
    func testPackageScriptExposesVersionMetadataAndSigningHook() throws {
        let script = try packageScriptContents()

        XCTAssertTrue(script.contains("MARKETING_VERSION"))
        XCTAssertTrue(script.contains("BUILD_NUMBER"))
        XCTAssertTrue(script.contains("CFBundleShortVersionString"))
        XCTAssertTrue(script.contains("CFBundleVersion"))
        XCTAssertTrue(script.contains("CFBundleGetInfoString"))
        XCTAssertTrue(script.contains("CFBundleSpokenName"))
        XCTAssertTrue(script.contains("LSApplicationCategoryType"))
        XCTAssertTrue(script.contains("NSPrincipalClass"))
        XCTAssertTrue(script.contains("SIGN_IDENTITY"))
        XCTAssertTrue(script.contains("codesign --force --sign"))
    }

    func testPackageScriptUsesTemporaryBundleBeforeReplacingFinalApp() throws {
        let script = try packageScriptContents()

        XCTAssertTrue(script.contains("TMP_BUNDLE_PATH"))
        XCTAssertTrue(script.contains("validate_bundle \"$TMP_BUNDLE_PATH\""))
        XCTAssertTrue(script.contains("safe_rm_app \"$BUNDLE_PATH\""))
        XCTAssertTrue(script.contains("mv \"$TMP_BUNDLE_PATH\" \"$BUNDLE_PATH\""))
    }

    func testPackageScriptValidatesRequiredBundleMetadata() throws {
        let script = try packageScriptContents()

        XCTAssertTrue(script.contains("validate_bundle()"))
        XCTAssertTrue(script.contains("plutil -lint \"$info_plist\""))
        XCTAssertTrue(script.contains("require_plist_value \"$info_plist\" CFBundleExecutable \"$PRODUCT\""))
        XCTAssertTrue(script.contains("require_plist_value \"$info_plist\" CFBundleIdentifier \"$BUNDLE_IDENTIFIER\""))
        XCTAssertTrue(script.contains("require_plist_value \"$info_plist\" CFBundlePackageType APPL"))
        XCTAssertTrue(script.contains("require_plist_value \"$info_plist\" LSMinimumSystemVersion \"$MIN_MACOS_VERSION\""))
    }

    func testPackageScriptEmbedsCLIHelperForLaunchAgent() throws {
        let script = try packageScriptContents()

        XCTAssertTrue(script.contains("CLI_PRODUCT"))
        XCTAssertTrue(script.contains("swift build -c \"$CONFIGURATION\" --product \"$CLI_PRODUCT\""))
        XCTAssertTrue(script.contains("cp \"$BIN_DIR/$CLI_PRODUCT\" \"$TMP_BUNDLE_PATH/Contents/MacOS/$CLI_PRODUCT\""))
        XCTAssertTrue(script.contains("Helper: Contents/MacOS/$CLI_PRODUCT"))
    }

    func testPackageScriptSupportsOptionalIcnsIconWithoutRequiringCertificate() throws {
        let script = try packageScriptContents()

        XCTAssertTrue(script.contains("APP_ICON_PATH"))
        XCTAssertTrue(script.contains("APP_ICON_NAME"))
        XCTAssertTrue(script.contains("CFBundleIconFile"))
        XCTAssertTrue(script.contains("cp \"$APP_ICON_PATH\" \"$TMP_BUNDLE_PATH/Contents/Resources/$ICON_RESOURCE_NAME\""))
        XCTAssertTrue(script.contains("require_plist_value \"$info_plist\" CFBundleIconFile"))
        XCTAssertTrue(script.contains("Set SIGN_IDENTITY='-' for ad-hoc signing"))
    }

    private func packageScriptContents() throws -> String {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("package_app.sh")
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }
}
