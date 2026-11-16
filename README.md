# Tricko

Tricko is a native SwiftUI app for importing, reviewing and editing local videos. Open **Review video** in the editor to mark a moment in the original footage, then tap its timecode to revisit it and mark it as reviewed. **Continue review** on Home opens the video with the most recent pending marker. Reopening a video resumes its saved playback time, marker selection, filter and list positions.

Use the marker categories to track visuals, audio, pacing, edit points and highlights. The practice log and magic notes are under **Tools → Practice resources**.

Open `Tricko.xcodeproj` and select the shared `Tricko` scheme. The minimum deployment target is iOS 17. The Duo layout paths use the iOS 27.1 SDK, which is available in Xcode 27.1.

## Service configuration

- API host `lvtppgv.tricko.website` and `getV2.name` `Tricko`.
- Xcode's effective `PRODUCT_BUNDLE_IDENTIFIER` sets the packaged Bundle ID. The guest login `source` and business `packageName` use `com.trickostudio.videodesk` from `TrickoConfiguration.servicePackageName`.
- AdMob App ID `ca-app-pub-4423220037289714~3524842188`. App-open and rewarded placements use the Google entries with `adType` 1 and 5 in `getV2.adList`.
- Plus requests `com.trickostudio.videodesk.plus.monthly` and `com.trickostudio.videodesk.plus.yearly`. The app displays prices and billing periods from StoreKit.
- [Official website](https://www.tricko.website), [Privacy Policy](https://www.tricko.website/privacy.html) and [Terms of Service](https://www.tricko.website/terms.html).

Check playback with a link or short code available in the configured environment. For purchase and restore verification, match the catalog IDs in App Store Connect and the backend `rightsName` mapping, then use an authorized Apple Sandbox account.

App-open ads wait for package configuration and verified non-Plus rights. The `AppOpen` log category records inventory loading, skips, presentation failures and impressions.

## Verification

Source, project settings and asset references were reviewed. Builds, live backend calls, playback, ad impressions, Apple transactions and iPhone Duo device behavior remain to be verified.
