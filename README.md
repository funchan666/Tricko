# Tricko

Tricko is a native SwiftUI app for importing, reviewing and editing local videos. Open **Review video** in the editor to mark a moment in the original footage, then tap its timecode to revisit it and mark it as reviewed. Markers stay with the local video, and **Continue review** on Home opens the latest pending marker.

Use the marker categories to track visuals, audio, pacing, edit points and highlights. The practice log and magic notes are under **Tools → Practice resources**.

Open `Tricko.xcodeproj` and select the shared `Tricko` scheme. The minimum deployment target is iOS 17. The Duo layout paths use the iOS 27.1 SDK, which is available in Xcode 27.1.

## Test configuration

- API host `devapi.io-jp.com` and `getV2.name` `Tricko`.
- Bundle ID `com.trickostudio.videodesk` in `Config/Tricko.xcconfig`. The guest login `source` and business `packageName` derive from this setting.
- Google iOS demo App ID, app-open and rewarded units.
- Plus requests `com.trickostudio.videodesk.plus.monthly` and `com.trickostudio.videodesk.plus.yearly`. The catalog has USD 9.99 and USD 99.99 reference prices. The app displays localized prices and billing periods from StoreKit.
- Website, terms and privacy point to HTTPS placeholders.

For playback integration, enter the Clipo test short code from the Toolkit on Home. Verify that the search result opens in the full-screen player. For purchase and restore verification, match the catalog IDs in App Store Connect and the backend `rightsName` mapping, then use an authorized Apple Sandbox account.

The demo app-open ad preloads during guest login. Its five-second cold-start window waits for verified non-Plus rights while package configuration loads independently. The `AppOpen` log category records inventory loading, skips, presentation failures and impressions.

## Production transition

After test acceptance, configure the production API domain, AdMob settings, official links and registered membership mapping. Check backend registration, receipt routing and signing against the effective Bundle ID and use `Tricko` as the release configuration name.

## Verification

Source, project settings and asset references were reviewed. Builds, live backend calls, playback, ad impressions, Apple transactions and iPhone Duo device behavior remain to be verified.
