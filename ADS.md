# Test advertisements

The library includes an adaptive Google AdMob test banner. Tap **Show test ad**
to load it; the SDK starts only after this action. Opening a title, video player,
source picker or settings removes the banner. Returning to the library requires
another tap. **Hide test ad** removes it, and failed requests offer **Retry ad**.

This build uses Google's demo application and banner IDs on both simulator and
physical devices. It cannot earn advertising revenue. `GADDelayAppMeasurementInit`
delays startup measurement until SDK initialization; publisher first-party IDs
and personalized ad treatment are disabled. Requests set `npa=1` and `rdp=1`.
These flags do not mean no data is sent: the UI explains that Google receives
connection/device information and links its privacy policy before loading.

No catalogue titles, searches, source URLs or torrent activity are sent as ad
targeting parameters. The banner is not placed in the video player.

The SDK is pinned to an official Google package revision in `project.yml`.
Replacing test IDs with live ads requires a separate implementation of the
advertising account, distribution eligibility, privacy disclosures and regional
consent flow. The test-only initialization guard deliberately rejects a different
application ID, so changing the plist alone cannot enable production ads.

Google integration references:
- https://developers.google.com/admob/ios/quick-start
- https://developers.google.com/admob/ios/banner
- https://developers.google.com/admob/ios/privacy/strategies

The automated smoke test initializes the actual SDK in a simulator and waits for
its banner delegate result. It accepts delivery or a handled network/no-fill
failure, since external ad serving is outside the app's control. Its log records
which result occurred; a passing test alone does not guarantee an ad was served.
