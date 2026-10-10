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
  In a WebView, Shopee's login page hides Google/Facebook sign-in (Google blocks OAuth in embedded
  WebViews). Users with Google-linked accounts use "Log In with Phone Number" (SMS code); the app
  shows a hint for this. Don't spoof the UA to bring the Google button back.

Seller data: Shopee (mobile UA serves the `item_basic` format) has `is_official_shop` (Mall),
`is_preferred_plus_seller`, `shopee_verified` (shown as Preferred — inferred, not confirmed),
`is_service_by_shopee`, `is_shopee_choice`, and `cb_option == 1` for cross-border sellers, who
often ship from a local warehouse (so location alone doesn't reveal them). Lazada has
`icons[].bizType` = `lazMall` / `lazPick` / `choice`; no preferred-seller field; `location` is
missing on ~22% of items and written "Metro Manila~Pasay".

## Price check (`lib/pricing/`)

Three tiers, decided with Jan: (1) a product in `assets/catalog.json` → its usual price range;
(2) else the robust median of ≥2 official (Mall/LazMall, incl. authorized resellers like Power Mac
Center) listings that claim the searched product and aren't accessories; (3) else no tags.
Listings that claim the product at < 0.6× usual get "Price looks off" (official store: green
"Big sale"); > 1.5× gets "Price looks high". Wording is always a nudge to check, never "fake".
Honest accessories ("case", "tips", catalog `exclude` phrases) get no tag, but "for…/compatible"
titles still do, since knockoffs use them. Titles that say they're made *for* the product
("For Original AirPods Pro2", "charger for MacBook", "compatible with") get a neutral
"Third-party item" tag instead, with or without a price reference; the brand's own official
listings are exempt. The catalog is a hand-curated bonus, not exhaustive:
prices come from official listings on the `checked` date; it ships no images (thumbnails are
learned on the phone from official listings). Discontinued products are worth adding: once
official stores stop selling them, tier 2 has nothing to go on.

- **Facebook Marketplace** — searched **logged out only, never with the user's account** (Meta's
  terms forbid automated collection; logged out, nothing lands on anyone's account). The mobile
  lite page omits listing links when logged out (`LOGGED_OUT_EXCLUDE_PERMALINK`), so this store
  uses the desktop page (desktop UA), which embeds `GroupCommerceProductItem` JSON in
  `<script type="application/json">` blobs. No condition field: it's inferred from title words.
  Location is only the city in the URL (`/marketplace/<slug or city-page id>/search`); lat/long
  and radius are ignored, and an unknown slug silently falls back to a network guess, so only add
  verified slugs to `marketplaceCities`. Seller names are deliberately not kept (private people).
  Price alerts use 0.35× instead of 0.6× here unless the title says brand new.

Store on/off and the Marketplace city live in `StoreSettings` (side menu). Marketplace defaults off.

Code: `lib/stores/` (one adapter per store, plus `store_runner.dart` for the hidden WebView),
`lib/queue/` (jobs; stores run in parallel within a job, max 2 jobs at once), `lib/ui/`.
Parsers are unit-tested against fixtures in `test/fixtures/`; extend them when a store's format
changes. Never commit real account data or cookies.

## Look

Two themes in `lib/ui/theme.dart`: **Dark Side** (default: near-black, neon red `#FF2E3E`, glow)
and **Light Side** (paper white, blue `#1F6BFF`), plus Auto; picked in the drawer, stored in
`StoreSettings.side`. Colors Material has no slot for (glow, hairlines, alert chips) live in the
`SiftColors` theme extension; don't hard-code colors in widgets. Orbitron (bundled, OFL) is for
the brand and section labels only: it has no ₱ glyph, so never for prices. Product photos sit on
white in both themes. Icon/splash come from `assets/icon/siftlord_icon_source.png` via
`tool/make_icons.py`, then `dart run flutter_launcher_icons` and
`dart run flutter_native_splash:create`; the iOS Main.storyboard view and Android NormalTheme are
black so there's no white flash while Flutter starts. The icon's hooded figure leans on a famous
Star Wars villain: fine for now, but if store review objects, soften the faceted mask/grille.

## Rules

- Commit author must be `Jan Aguja <jan.aguja@gmail.com>` (or the GitHub noreply address), never a
  work email. In any fresh clone, run
  `git config user.name "Jan Aguja" && git config user.email jan.aguja@gmail.com` first.
- `flutter_inappwebview` is pinned to `6.2.0-beta.3`: 6.1.5's Android module uses
  `proguard-android.txt`, which AGP 9 rejects. Move to 6.2.0 stable when it ships.
- iPhone is portrait-only (Info.plist).
- Before reporting work done, run `flutter analyze`, `flutter test`, `flutter build apk --debug`
  and `flutter build ios --simulator --debug`.
