# Globalization plan

Written 2026-10-11, after the Zalora/Datablitz round (commit `018f875`).

**Status (2026-10-11, later the same day):** Amazon US/JP/UK are in, so part of phases 1, 2 and 5
is done: `Item.currency` + `Item.country`, `StoreAdapter.country/currency`, `formatMoney`,
`Rates` (ECB via Frankfurter, daily, cached), a "Show prices in" currency setting (default PHP),
converted "≈" prices, "From" and price sorting in the user's currency, and the price check
limited to in-market listings. Still open: country onboarding and storefronts grouped by country
(phase 3), per-market catalog prices (phase 4), and the open questions below. Note one finding:
Amazon converts to pesos itself for PH visitors, so currency never implies country. Read `CLAUDE.md` first: the model there (searches run on the
phone, in hidden WebViews, as the user; no affiliate programs or approval-gated APIs) is unchanged.

## Why

Sift Lord isn't a Philippine app. The PH stores are where it started, but Jan buys from Amazon US,
JP and UK too, and the app shouldn't be marketed as PH-specific. Today every price is a bare
number assumed to be pesos. That works only because every store we open is a PH site.

## Decided with Jan

- **Storefronts, not stores.** A storefront is one store in one country, with one currency:
  Lazada PH (lazada.com.ph, PHP), Shopee PH (shopee.ph, PHP), Amazon US (amazon.com, USD),
  Amazon JP (amazon.co.jp, JPY), Amazon UK (amazon.co.uk, GBP). The site decides the currency, not
  where the user is: Lazada PH shows pesos even from the US. We never mix countries within a
  storefront (shopee.ph only, never shopee.com.my unless someone adds Shopee MY on purpose).
- **Country by country.** Onboarding asks for the user's country. That suggests a default currency
  (changeable) and pre-checks that country's recommended storefronts. Other countries'
  storefronts are listed below, unchecked, easy to add (PH user + Amazon US/JP/UK is a real case).
- **Show both prices.** A foreign listing shows its own price plus the converted one in the
  user's currency: "¥4,980 · about ₱1,920".

## Today's peso assumptions (what has to change)

- `Item.price`, `originalPrice`, `priceBeforeVouchers` are bare doubles "in pesos"
  (`lib/models/item.dart`).
- `formatPeso` / `formatPriceRange` in `lib/ui/store_style.dart`, used in 15 places across
  `item_card.dart`, `results_screen.dart`, `home_screen.dart`.
- Catalog prices are pesos (`assets/catalog.json`, `CatalogEntry.minPrice/maxPrice`).
- `PriceCheck` compares raw numbers; tier 2's official-store median mixes whatever's in the
  results.
- Adapters mention pesos in parsing only (Zalora's "Php 5,500.00" text fallback, Shopee's ×100,000
  scale); those stay, they're facts about PH sites.
- `searches.json` (`SearchArchive`) stores items without a currency.
- `StoreSettings` has store on/off and the Marketplace city; no country or currency.
- Copy: drawer subtitles and hints are PH-neutral already; check again once Amazon lands.

## Design

### 1. Money and storefronts

- `StoreAdapter` gains `String get country` (ISO 3166, e.g. `PH`, `US`, `JP`, `GB`) and
  `String get currency` (ISO 4217: `PHP`, `USD`, `JPY`, `GBP`). Existing adapters return `PH` /
  `PHP`. Keep existing store ids (`lazada`, `shopee`, `zalora`, `datablitz`, `facebook`) so saved
  searches, settings and sign-ins don't need migrating; new ones carry the country in the id
  (`amazon-us`, `amazon-jp`, `amazon-uk`). One adapter class can serve several storefronts
  (an `AmazonAdapter(country: 'JP')` with host, currency and parsing quirks per country).
- `Item` gains `currency` (set by the adapter; JSON key `cur`). Old saved items without it read
  as their storefront's currency, so `searches.json` needs no migration step.
- One formatter, `formatMoney(amount, currency)`, replacing `formatPeso`: symbol and decimals
  per currency (JPY has none, PHP/USD/GBP two), using `intl`'s `NumberFormat.simpleCurrency` or a
  small table. Prices never use Orbitron (no ₱ glyph; ¥/£ unchecked too).

### 2. Exchange rates

- Source: the European Central Bank's daily reference rates, which include PHP, USD, JPY, GBP,
  MYR, SGD and more. Free, public, no key, nothing to approve. Fetch on the phone at most once a
  day (e.g. `https://api.frankfurter.app/latest?from=PHP`, which serves ECB data, or the ECB XML
  directly), cache the table and its date in SharedPreferences, and fall back to the last cached
  table offline. No server.
- A `Rates` service: `convert(amount, from, to)`, returns null when a rate is missing (then show
  the original price only).
- UI wording: "about ₱1,920" and, in details, "converted at the 2026-10-10 rate". Never imply the
  converted figure is what the card will be charged.

### 3. Settings and onboarding

- `StoreSettings` gains `homeCountry` and `homeCurrency` (default `PH` / `PHP` for existing
  installs, so Jan's current setup is untouched).
- A storefront registry: each storefront lists its country and whether it's recommended for that
  country (PH: Lazada, Shopee, Zalora, Datablitz; Marketplace stays opt-in).
- First launch (no `homeCountry` saved yet): a short onboarding with three steps.
  1. Country: suggested from the phone's locale.
  2. Currency: preset from the country, changeable.
  3. Storefronts: home country's recommended ones checked; "Shop abroad too?" lists others,
     unchecked.
  The drawer gets the same controls afterwards (country, currency, storefronts grouped by
  country, recently turned on first, as now).
- Countries with no storefronts yet: allow picking them (for the currency) and show foreign
  storefronts only, with a note that local stores are coming.

### 4. Price check across countries

- Catalog v2: prices per market. Keep reading v1 (top-level `price` means PH).
  ```json
  "prices": {
    "PH": {"currency": "PHP", "min": 64990, "max": 85990, "checked": "2026-10-11"},
    "US": {"currency": "USD", "min": 799, "max": 999, "checked": "2026-10-20"}
  }
  ```
- A listing is checked against its own storefront's market, in its own currency. A US$799 iPhone
  on Amazon US is judged against the US price, not against pesos. No market price for that
  country means tier 2 (official listings) or no tag, as today.
- Tier 2's official-store median is computed per currency, never mixing pesos with dollars.
- The reference bar on results shows the home market's usual price; foreign markets' usual
  prices show on their listings' tags.
- Sorting by price and the queue's "From" compare converted amounts in the home currency. "From"
  keeps today's exclusions and says when it's foreign: "From ₱1,920 (¥4,980) on Amazon JP".

### 5. Shipping and fees (be honest about them)

Buying from Amazon US to the Philippines isn't the listed price: international shipping and
import fees come on top. First version: show the item price only, labelled "plus shipping and
import fees" on foreign listings. Landed cost is a later step, only if Amazon's search results
actually expose it (see the spike).

### 6. Amazon (spike first, before building)

Amazon is stricter about automation than Lazada was. Before writing the adapter, check in the
real setup (hidden `HeadlessInAppWebView` on iOS and Android, logged out, then signed in in our
visible WebView):

- Does the search page (`/s?k=…`) render results without a CAPTCHA/robot check, mobile and
  desktop UA? How fast do repeated searches trip it? The adapter must map it to
  `PageKind.verification` so the user can clear it, like Lazada's slider. Never solve it for them.
- Where the data lives: server-rendered HTML (`div[data-component-type="s-search-result"]`,
  `data-asin`) vs embedded JSON. Expect a DOM-reading load-stop script.
- Sponsored results (mark `isAd`), price fields (whole + fraction, "List Price" strikethrough),
  Prime/fulfilled by Amazon (`fulfilledByStore`), "Amazon.com" as seller vs third-party, ratings,
  "bought in past month" (sold text).
- Delivery location: logged out, Amazon guesses it from the IP. Can the user set "Deliver to
  Philippines" on Amazon's own page in our visible WebView, and does it stick in the cookies the
  hidden WebViews share? Do results then show "ships to Philippines" / shipping cost?
- Per-country differences: amazon.co.jp markup and yen formatting, amazon.co.uk.
- App links: does `amazon.com/dp/<ASIN>` open the Amazon app per country?

Write findings into `CLAUDE.md` like the other stores ("How each store is read").

## Phases

1. **Money plumbing:** add `currency` on adapters and items, `formatMoney`, update the 15 call
   sites. No visible change for PH users. Tests: JSON round-trip with and without `cur`,
   formatting per currency.
2. **Rates:** the `Rates` service with daily cache and offline fallback, and converted prices on
   foreign listings. Tests with a fake rate table.
3. **Country, currency and onboarding:** settings, onboarding screen, drawer grouped by country.
   Existing installs default to PH/PHP and skip onboarding.
4. **Price check per market:** catalog v2 reader (v1 still works), per-currency tier 2,
   converted "From" and price sorting. Extend `pricing_test.dart`.
5. **Amazon spike** (can run in parallel with 1 to 4), then the Amazon US/JP/UK adapters with
   fixtures and parser tests, as for the other stores.
6. **Jan's store list:** add storefronts from his testing list one at a time, each verified like
   Zalora and Datablitz were.

## Open questions for Jan

- Which countries ship first besides PH (US, JP and UK as shopping destinations; are there any
  home countries besides PH to support now)?
- Should foreign storefronts' results mix into the same list as local ones, or show as their own
  group/filter by default?
- Conversion display: the converted price big and the original small, or the other way round?
- Is "plus shipping and import fees" enough for now, or is landed cost a must-have for Amazon?
- Catalog: who maintains non-PH prices? (Same approach as PH: official stores only, dated.)
