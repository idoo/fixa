# Writing an adapter

An adapter is one JSON file in `adapters/` that tells Fixa how to file a report with one municipality. It is validated by `schema/adapter.schema.json` and decoded into `AdapterSpec` (FixaKit). `adapters/` is the source of truth; FixaKit ships a byte-identical copy in `FixaKit/Sources/FixaKit/Resources/adapters/`, and a test fails if the two drift:

```sh
cp adapters/*.json FixaKit/Sources/FixaKit/Resources/adapters/
```

Today the only channel kind is `abou`, the Abou e-service platform (ASP.NET WebForms) that many Swedish municipalities use.

## Fields

| Key | What it is |
|---|---|
| `specVersion` | Adapter format version, `1` today. An app ignores a remote adapter with a newer version than it supports. |
| `minAppBuild` | Optional. Lowest app build (`CFBundleVersion`) that can run this adapter. Older builds keep their bundled copy. |
| `id` | Reverse-DNS id, e.g. `se.varmdo.ksb`. Stored in every draft. |
| `municipality` | `name`, `countryCode`, and `region` with `center` and `bbox` (WGS84). The map opens on the region and the validator warns when the pin is outside the bbox. |
| `channel` | How to reach the e-service; see below. |
| `categories` | `id` (your stable slug), `value` (the exact `<option value>` of the form's category dropdown), optional `synonyms` (see Resilience) and a localized `title`. |
| `tiles` | The home grid: `id`, `symbol` (SF Symbol), `categoryID`, localized `title`, and `swedishSummary`, which becomes the first line of the description sent to the municipality. Optional localized `responsibility`: a short note on who looks after this kind of problem, for tiles where the municipality is not always the right place (Värmdö's road tiles: municipal streets vs Trafikverket's state roads and private road associations). |
| `validation` | `descriptionMin`, `descriptionMax`, `emailRequiredWhenFeedback`, `requireLocation` (a pin or a place text). |
| `emergency` | Optional. Phone `contacts`, `rules` (`isoWeekdays` 1 = Monday, `until` "HH:mm" local, `contactID`), `defaultContactID` when no rule matches, `timeZone`, and a localized `note`. |
| `fallbackEmail` | Optional. Where the "send by e-mail instead" fallback goes. |
| `disclaimer` | Localized. Shown before sending. The app always shows the disclaimer of the adapter it shipped with, never a downloaded one. |

Localized texts are plain objects keyed by language code: `{"sv": "…", "en": "…", "ru": "…", …}`, one key per app language (`en sv cs da de et es fr it lv lt hu nl nb pl pt ro fi el ru uk ar`). `sv` and `en` are required; a missing language falls back to English, then Swedish.

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

Each field is `{ "role", "key", "control" }`, plus `yesValue`/`noValue` for radio fields, and optionally `type`, `labels` and `optionSynonyms` (see Resilience). Roles: `category`, `place`, `mapChoice`, `mapAnswer`, `description`, `feedback`, `firstName`, `lastName`, `phone`, `email`. The submitter finds the real input name on the live page by matching `name="…$<key>_field$<control>"`, so never paste full ASP.NET names.

## Resilience

Municipalities edit their e-services. The submitter tolerates small changes and reports the rest as drift instead of sending a broken form.

- **Fields**: exact `key` + `control` first, then the same `key` with the same kind of input, then a control of the same `type` (`select`, `radio`, `text`, `textarea`, `hidden`, `checkbox`) or `control` class under a question whose label matches one of `labels` (`{"sv": ["Beskriv felet här"], "en": […]}`). Labels compare case- and diacritic-insensitively and ignore `*`, a trailing `:` and extra spaces.
- **Options** (dropdowns, radios): exact value, then the visible text or value after the same normalisation, then `categories[].synonyms` or the field's `optionSynonyms` (`{"Ja": ["Ja tack"]}`, keyed by `yesValue`/`noValue`).
- **Pages**: by `PageId`, or, if the id was renamed, by finding all of a page's fields on it. Pages without fields (the summary) are matched by id only.
- **Drift**: anything else throws `SubmissionError.formChanged(FormDrift)` with `pageID`, `missing` (labels of fields or options Fixa can't fill, and of new required questions, the ones with a visible `*`) and a one-sentence `detail`. Network and server answers stay `transport`, `http`, `sessionLocked` and `serverValidation`.
- **Session lost**: before the final send, a page with `sessionLockedMarker`, the platform's `GenericError` page, or a bounce back to `introPath` (the session expired) makes the submitter start over once from `introPath` with fresh cookies. A second loss surfaces as `sessionLocked` (lock) or `transport` (expiry).
- **Final send**: posting the summary page is the one request that creates the case. It is sent exactly once. If it, or the ThankYou re-posts after it, time out, fail, redirect, or end on a page that shows neither a case number nor received-wording ("Tack", "tagit emot", "kvittens"), the submitter throws `SubmissionError.uncertain`. Nothing after that point is retried or restarted. `SubmissionError.isRetrySafe` is true only for `transport`, `http` and `unavailable`, which can only happen before the final send; the app must never resend an `uncertain` report automatically.
- **Server down**: before the final send, 429 and any 5xx become `unavailable(status, retryAfter)` (`Retry-After` read as seconds or a date, capped at 24 h), and so does a maintenance page served with 200. A login page served with 200 is `formChanged`. Neither is ever read as a receipt.
- **Host**: requests go only to the adapter's host over https. Redirects off that host are not followed, and a form posting elsewhere is `formChanged`.
- **Pace**: 400 ms between page requests, like a person moving through the form.
- **Looks like the website**: Safari's User-Agent and headers, a WebKit-style multipart boundary and a camera-style photo name (`IMG_1234.jpg`). Nothing sent to the municipality names Fixa.
- **Timeouts**: `SubmissionTimeouts.page` (30 s) for every page request, `SubmissionTimeouts.upload` (120 s) for the photo upload.

`fixa-cli dry-run` exits 2 on drift (1 on any other failure), so you can tell "the form changed" from "the site was down". Run it by hand only, when a user reports a failed send or before changing an adapter: there is no scheduled job, so the municipality's e-service is never exercised automatically. When it reports drift, capture the new page, add the new texts to `labels`/`synonyms` or update `key`, and add a fixture test.

## When a municipality changes its form

The app downloads `adapters/<id>.json` and `adapters/status.json` from `main` on GitHub (raw.githubusercontent.com), each with its signature `<name>.sig`, only after a send has failed with `formChanged`, and at most every 15 minutes (`AdapterStore.refreshAfterFormChange`). Never on launch or on a timer. If a newer adapter is accepted, the app retries that send once (drift stops before the final step, so this can't create a second case). A downloaded adapter replaces the bundled one only if its signature verifies, it decodes, passes the same consistency checks as the bundled copy (`AdapterSpec.problems`), has the same `id`, a `specVersion` the app supports, and a `minAppBuild` no higher than the installed build. A status file is used only if its signature verifies. Otherwise the app keeps what it has. A fix that only needs JSON therefore needs no App Store release.

1. **Notice.** A send that hits a changed form stops before the final step with a drift report, and the app offers e-mail instead. There is no automatic check against the live e-service: Fixa never sends test traffic to the municipality.
2. **Status.** Set the adapter's `state` in `adapters/status.json` to `degraded` by hand and sign the file (below). Apps read it the next time a send hits the changed form and show their own banner on Home. The file carries only `state` and optional `updated` (`schema/status.schema.json`); there is no message field, the app words each state itself. Reports stay saved and can still go by e-mail.
3. **Fix.** Run `swift run fixa-cli dry-run --save-html page.html` once locally, then update `key`, `labels` or `synonyms` in `adapters/<id>.json`, copy it into `FixaKit/Sources/FixaKit/Resources/adapters/`, sign it, and add a fixture test.
4. **Push** to `main` and set the status back to `ok` (signed again). A phone picks up the new adapter the next time its send hits the changed form, and retries that send.

Bump `minAppBuild` only when the adapter needs an engine change (a new field role, a new channel kind). Then ship the new build first; older builds keep their bundled adapter and keep showing the status banner. Set `state` to `down` (signed) by hand in `status.json` if the e-service is off entirely.

### Signing

Every file the app downloads needs a valid Ed25519 signature, or the app ignores it. The public key is `AdapterSignature.publicKeyBase64` in `FixaKit/Sources/FixaKit/AdapterUpdate.swift`; the private key lives only on the maintainer's Mac at `~/.config/fixa/adapter-signing.key` (mode 600, never committed; `*.key` is in `.gitignore`).

```sh
cd FixaKit
swift run fixa-cli sign ../adapters/se-varmdo-ksb.json   # writes ../adapters/se-varmdo-ksb.json.sig
swift run fixa-cli sign ../adapters/status.json          # writes ../adapters/status.json.sig
```

Sign after the last edit and commit the `.sig` with the JSON: a signature covers the exact bytes, so even reformatting the file invalidates it. `AdapterSecurityTests.testPublishedFilesVerifyAgainstEmbeddedKey` fails if a committed `.sig` does not match. To rotate the key (lost or leaked), run `fixa-cli keygen` on a fresh path, put the printed public key into `AdapterSignature.publicKeyBase64`, re-sign every file, and ship an app build; builds with the old key keep their bundled or last accepted copy.

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
swift run fixa-cli dry-run                                   # street-light tile, point, reply wanted
swift run fixa-cli dry-run --category lighting --category roads --no-point --feedback no
swift run fixa-cli dry-run --all-categories --delay 5        # every category, one after another
swift run fixa-cli dry-run --photo foto.jpg                  # also uploads the photo (to the unsent case)
```

`fixa-cli submit --live --i-understand-this-creates-a-real-case [--photo foto.jpg] [--save-html receipt.html]` creates a **real** case. Only use it when you have agreed with the municipality to send a test case, then capture the receipt page as a new fixture.

## Capturing real pages

Fixtures should be real pages, saved byte for byte. Two ways to get them:

- **`fixa-cli dry-run`** (above) walks every page up to the summary without creating a case. Use it to check field keys and to capture form pages.
- **App launch hook `-FixaLiveTest 1`** (DEBUG builds only). It seeds a report marked TEST and records every response to the app's `Caches/fixa-responses` folder. Sending is **real**: it creates a case with the municipality. Use it sparingly, only to capture pages that a dry run cannot reach (the ThankYou and receipt pages).

Copy the captured pages into `FixaKit/Tests/FixaKitTests/Fixtures/` with a numbered name (e.g. `08-thankyou-processing.html`, `09-thankyou-receipt.html`) and add a parser or submitter test that replays them.
