# Sift Lord (repo: siftlord)

Flutter app (Android + iOS) that searches Lazada PH and Shopee PH at once and shows the results as
calm, ad-free cards; tapping one opens the product in the store's own app. Bundle/app ID:
`com.jandroid.siftlord`. Stage: proof of concept for Jan and his wife. No monetization work yet.

## The model (decided — don't re-propose alternatives)

- Searches run **on the user's phone, in hidden WebViews, as that user** (a browser, not a scraper).
  No server, no affiliate programs, no approval-gated store APIs: nothing a store can revoke with
  one switch.
- Logins belong to the user: they sign in on the store's own page inside our WebView
  (`StoreWebScreen`). Cookies are shared with the hidden WebViews. We never see credentials.
- POC scope is Lazada + Shopee only. Generic "any store" extraction comes later.

## How each store is read (verified 2026-10-11)

- **Lazada** — works logged out. The mobile page embeds results in `window.pageData.mods.listItems`;
  with a desktop UA it doesn't, so the script falls back to same-origin
  `/catalog/?ajax=true&q=…` (same JSON shape). Search often redirects to a `/tag/…` SEO page; fine.
  Ads: `isSponsored == true` or `adFlag == "1"`. Anti-bot shows a `punish` slider page.
- **Shopee** — a document-start script wraps `fetch`/XHR and forwards the
  `/api/v4/search/search_items` response. Prices are integers × 100,000. Logged out, it sometimes
  works and sometimes redirects to `/verify/traffic/error` ("Login Required") with
  `{"error":90309999}`; the app then shows "sign in". Ads: `search_item_tracking.is_ads`.
  Product URL: `shopee.ph/product/{shopid}/{itemid}`.

Code: `lib/stores/` (one adapter per store, plus `store_runner.dart` for the hidden WebView),
`lib/queue/` (jobs; stores run in parallel within a job, max 2 jobs at once), `lib/ui/`.
Parsers are unit-tested against fixtures in `test/fixtures/`; extend them when a store's format
changes. Never commit real account data or cookies.

## Rules

- Commit author must be `Jan Aguja <jan.aguja@gmail.com>` (or the GitHub noreply address), never a
  work email. In any fresh clone, run
  `git config user.name "Jan Aguja" && git config user.email jan.aguja@gmail.com` first.
- `flutter_inappwebview` is pinned to `6.2.0-beta.3`: 6.1.5's Android module uses
  `proguard-android.txt`, which AGP 9 rejects. Move to 6.2.0 stable when it ships.
- iPhone is portrait-only (Info.plist).
- Before reporting work done, run `flutter analyze`, `flutter test`, `flutter build apk --debug`
  and `flutter build ios --simulator --debug`.
