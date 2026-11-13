# Tricko

Close-up magic video lessons in a native SwiftUI iPhone app. Routine rehearsal by discipline and setting, with performance notes.

Open `Tricko.xcodeproj` and select the shared `Tricko` scheme. The minimum deployment target is iOS 17. The Duo layout paths use the iOS 27.1 SDK, which is available in Xcode 27.1.

## Test configuration

- API host `devapi.io-jp.com` and `getV2.name` `Tricko`.
- Bundle ID `im.seex.lobo` in `Config/Tricko.xcconfig`. The guest login source and business package name derive from the same setting. These test apps share a Bundle ID, so install them one at a time.
- Google iOS demo App ID, app-open and rewarded units. Membership requests `coins_1.99` monthly (USD 9.99) and `conis_4.99` yearly (USD 99.99) in Apple Sandbox. The app displays the prices returned by StoreKit.
- Website, terms and privacy point to HTTPS placeholders.

For playback integration, enter the Clipo test short code from the Toolkit on Home. Verify that the search result opens in the full-screen player. Use a new or authorized test account when verifying Apple purchases and restores.

## Production transition

After test acceptance, update the Bundle ID, API domain, AdMob configuration, official links and registered membership mapping for this app. The release configuration name stays `Tricko`. Check backend registration, receipt routing and signing against the effective build settings.

## Verification

Source, project settings and asset references were reviewed. Builds, live backend calls, playback, ad impressions, Apple transactions and iPhone Duo device behavior remain to be verified.
