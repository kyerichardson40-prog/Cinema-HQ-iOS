import XCTest
import UIKit
@testable import CinemaHQ

final class AdvertisementTests: XCTestCase {
    func testAppUsesGoogleDemoApplicationIdentifier() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
                       TestAdConfiguration.applicationID)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "GADDelayAppMeasurementInit") as? Bool, true)
    }

    @MainActor
    func testTestBannerInitializesAndReceivesSDKResponse() async throws {
        let response = expectation(description: "Google test banner returns an SDK result")
        var completed = false
        var measuredHeight: CGFloat = 0
        var finalMessage: String?
        let controller = TestBannerController(onHeight: { measuredHeight = $0 }, onStatus: { message, _ in
            guard !completed else { return }
            completed = true
            finalMessage = message
            response.fulfill()
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 150))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        defer { controller.dispose(); window.isHidden = true }
        await fulfillment(of: [response], timeout: 60)
        XCTAssertGreaterThan(measuredHeight, 0, "SDK initialization must finish and calculate an adaptive size.")
        XCTAssertLessThanOrEqual(measuredHeight, 150)
        // External ad serving can be unavailable; either delegate result must be
        // handled without crashing. Logs distinguish real delivery from failure.
        XCTAssertNotNil(finalMessage)
        print("Test banner SDK result: \(finalMessage ?? "no response")")
    }
}
