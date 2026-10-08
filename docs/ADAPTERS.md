# Writing an adapter

An adapter is one JSON file in `adapters/` that tells Fixa how to file a report with one municipality. It is validated by `schema/adapter.schema.json` and decoded into `AdapterSpec` (FixaKit). `adapters/` is the source of truth; FixaKit ships a byte-identical copy in `FixaKit/Sources/FixaKit/Resources/adapters/`, and a test fails if the two drift:

```sh
cp adapters/*.json FixaKit/Sources/FixaKit/Resources/adapters/
```

Today the only channel kind is `abou`, the Abou e-service platform (ASP.NET WebForms) that many Swedish municipalities use.

## Fields

| Key | What it is |
|---|---|
| `specVersion` | Always `1`. |
| `id` | Reverse-DNS id, e.g. `se.varmdo.ksb`. Stored in every draft. |
| `municipality` | `name`, `countryCode`, and `region` with `center` and `bbox` (WGS84). The map opens on the region and the validator warns when the pin is outside the bbox. |
| `channel` | How to reach the e-service; see below. |
| `categories` | `id` (your stable slug), `value` (the exact `<option value>` of the form's category dropdown) and a localized `title`. |
| `tiles` | The home grid: `id`, `symbol` (SF Symbol), `categoryID`, localized `title`, and `swedishSummary`, which becomes the first line of the description sent to the municipality. |
| `validation` | `descriptionMin`, `descriptionMax`, `emailRequiredWhenFeedback`, `requireLocation` (a pin or a place text). |
| `emergency` | Optional. Phone `contacts`, `rules` (`isoWeekdays` 1 = Monday, `until` "HH:mm" local, `contactID`), `defaultContactID` when no rule matches, `timeZone`, and a localized `note`. |
| `fallbackEmail` | Optional. Where the "send by e-mail instead" fallback goes. |
| `disclaimer` | Localized. Shown before sending. |

Localized texts are plain objects keyed by language: `{"sv": "…", "en": "…", "fi": "…", "ar": "…", "uk": "…", "pl": "…"}`. `sv` and `en` are required; the app falls back to English, then Swedish.

### `channel` (kind `abou`)

| Key | What it is |
|---|---|
| `baseURL` | e.g. `https://service.varmdo.se`. |
| `service` | The e-service code, e.g. `KSB`. |
| `introPath` | Intro page that sets the session cookie, e.g. `/KSB`. |
| `startPath` | Starts a fresh case, e.g. `/Setup.aspx?Service=KSB&skipintro=true`. |
| `nextEventTarget` | `__EVENTTARGET` of the Next button (it reads "Slutför" on the summary page). |
| `completionPostBackMarker` | Optional. Text on the page after Slutför meaning the browser would now post the form again by script. Abou's ThankYou page runs `__doPostBack('', '')` on load ("Dina uppgifter bearbetas, vänligen vänta…"); for Värmdö the marker is `var doPostBack = 'True'`. While the page contains it, Fixa re-posts the form with an empty `__EVENTTARGET`, then reads the receipt (e.g. "Här är ditt ärendenummer 261026-KSB-KS43"). |
| `maxCompletionPostBacks` | Optional. Upper bound for those re-posts; default 3. |
| `sessionLockedMarker` | Text shown when the session already has an open case. |
| `pages` | Pages in the order the platform shows them. Each has `id` (the `PageId` query value), `stage` (`sendingReport`, `sendingContact`, `confirming`) and `fields`. The **last** page is the summary; posting it submits the case. The server may skip a page (Värmdö skips contact details when no reply is wanted); the submitter accepts landing on any later page. |
| `upload` | Optional photo upload: `pageID` it precedes, `fieldID` (e.g. `U.29.1.2`), `path`, `filePartName`, `fileName`, and `actionPath` used to verify with `getFiles`. |

Each field is `{ "role", "key", "control" }`, plus `yesValue`/`noValue` for radio fields. Roles: `category`, `place`, `mapChoice`, `mapAnswer`, `description`, `feedback`, `firstName`, `lastName`, `phone`, `email`. The submitter finds the real input name on the live page by matching `name="…$<key>_field$<control>"`, so never paste full ASP.NET names.

## Finding the Abou field keys

1. Open the e-service in a browser and fill in a page.
2. Save the page HTML (or `curl` it with a cookie jar: `GET /<service>`, then `GET <startPath>`).
3. Search the HTML for `_field$`. Each input name ends in `$<KEY>_field$<CONTROL>`, e.g. `…$KSB_14_field$dropDownListFieldControl`. The `<label>` above it tells you what the field means.
4. For dropdowns and radios, copy the exact `value` attributes into `categories[].value` or `yesValue`/`noValue`.
5. The page id is the `PageId` in the form's `action`.
6. Post the page empty once: required fields come back as `<label class="validation-error-label">` messages, which tells you what the server insists on.
7. For uploads, watch the browser's network tab: the multipart POST path and the file part name.

## Testing

Save one HTML page per step as fixtures in `FixaKit/Tests/FixaKitTests/Fixtures/` (clean page, the page after an empty POST, summary, and the session-lock page) and add tests in the style of `AbouPageParserTests` and `AbouSubmitterTests`. The submitter tests replay fixtures through a fake `HTTPTransport`, so they never touch the network.

```sh
cd FixaKit
swift test
```

## Dry run against the live site

`fixa-cli dry-run` fills every page with a report marked `TEST — ignorera` and stops at the summary page. No case is created; the session expires on its own.

```sh
cd FixaKit
swift run fixa-cli dry-run
```

`fixa-cli submit --live --i-understand-this-creates-a-real-case [--photo foto.jpg] [--save-html receipt.html]` creates a **real** case. Only use it when you have agreed with the municipality to send a test case, then capture the receipt page as a new fixture.

## Capturing real pages

Fixtures should be real pages, saved byte for byte. Two ways to get them:

- **`fixa-cli dry-run`** (above) walks every page up to the summary without creating a case. Use it to check field keys and to capture form pages.
- **App launch hook `-FixaLiveTest 1`** (DEBUG builds only). It seeds a report marked TEST and records every response to the app's `Caches/fixa-responses` folder. Sending is **real**: it creates a case with the municipality. Use it sparingly, only to capture pages that a dry run cannot reach (the ThankYou and receipt pages).

Copy the captured pages into `FixaKit/Tests/FixaKitTests/Fixtures/` with a numbered name (e.g. `08-thankyou-processing.html`, `09-thankyou-receipt.html`) and add a parser or submitter test that replays them.
