import SwiftUI
import GoogleMobileAds

enum TestAdConfiguration {
    // Google's dedicated demo identifiers: this build cannot request paid ads.
    static let applicationID = "ca-app-pub-3940256099942544~1458002511"
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    static func makeRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1", "rdp": "1"]
        request.register(extras)
        return request
    }
}

@MainActor
private enum TestAdService {
    private static var initialization: Task<Bool, Never>?
    static func prepare() async -> Bool {
        if let initialization { return await initialization.value }
        let task = Task { @MainActor in
            guard Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String ==
                    TestAdConfiguration.applicationID else { return false }
            MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
            MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                MobileAds.shared.start { _ in continuation.resume() }
            }
            return true
        }
        initialization = task
        return await task.value
    }
}

struct LibraryAdvertisement: View {
    @State private var enabled = false
    @State private var height: CGFloat = 100
    @State private var status = "Loading test ad…"
    @State private var failed = false
    @State private var attempt = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Advertisement · Test ad").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if enabled {
                    Button {
                        enabled = false
                        status = "Loading test ad…"
                        failed = false
                    } label: { Image(systemName: "xmark.circle") }
                        .accessibilityLabel("Hide test ad")
                }
            }
            if enabled {
                TestBannerContainer(onHeight: { height = $0 }, onStatus: { message, failure in
                    status = message
                    failed = failure
                })
                .id(attempt)
                .frame(height: height)
                Text(status).font(.caption).foregroundStyle(.secondary)
                if failed {
                    Button("Retry ad") {
                        failed = false
                        status = "Loading test ad…"
                        attempt = UUID()
                    }
                }
            } else {
                Text("Preview a Google test advertisement. Test ads do not earn money.")
                    .font(.footnote)
                Text("Loading an ad shares connection and device information with Google.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Show test ad") { enabled = true; attempt = UUID() }
                        .buttonStyle(.bordered)
                    Link("Privacy", destination: URL(string: "https://policies.google.com/privacy")!)
                        .font(.footnote)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TestBannerContainer: UIViewControllerRepresentable {
    let onHeight: (CGFloat) -> Void
    let onStatus: (String, Bool) -> Void
    func makeUIViewController(context: Context) -> TestBannerController {
        TestBannerController(onHeight: onHeight, onStatus: onStatus)
    }
    func updateUIViewController(_ controller: TestBannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: TestBannerController, coordinator: ()) {
        controller.dispose()
    }
}

@MainActor
final class TestBannerController: UIViewController, BannerViewDelegate {
    private let banner = BannerView()
    private let onHeight: (CGFloat) -> Void
    private let onStatus: (String, Bool) -> Void
    private var loadedWidth: CGFloat = 0
    private var loadTask: Task<Void, Never>?
    private var disposed = false

    init(onHeight: @escaping (CGFloat) -> Void, onStatus: @escaping (String, Bool) -> Void) {
        self.onHeight = onHeight
        self.onStatus = onStatus
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(onHeight:onStatus:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        banner.adUnitID = TestAdConfiguration.bannerUnitID
        banner.delegate = self
        banner.rootViewController = self
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = floor(view.bounds.width)
        guard !disposed, width >= 120, width != loadedWidth else { return }
        loadedWidth = width
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let ready = await TestAdService.prepare()
            guard !Task.isCancelled, let self, !self.disposed else { return }
            guard ready else {
                self.onStatus("Test ads are unavailable in this build.", true)
                return
            }
            let size = largeAnchoredAdaptiveBanner(width: width)
            self.banner.adSize = size
            self.onHeight(size.size.height)
            self.banner.load(TestAdConfiguration.makeRequest())
        }
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        guard !disposed else { return }
        onStatus("Test advertisement · No revenue", false)
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        guard !disposed else { return }
        onStatus("The test ad could not load. Check your connection and try again.", true)
    }

    func dispose() {
        disposed = true
        loadTask?.cancel()
        loadTask = nil
        banner.delegate = nil
        banner.rootViewController = nil
        banner.removeFromSuperview()
    }
}
