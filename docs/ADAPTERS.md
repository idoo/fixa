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

Each field is `{ "role", "key", "control" }`, plus `yesValue`/`noValue` for radio fields, and optionally `type`, `labels` and `optionSynonyms` (see Resilience). Roles: `category`, `place`, `mapChoice`, `mapAnswer`, `description`, `feedback`, `firstName`, `lastName`, `phone`, `email`. The submitter finds the real input name on the live page by matching `name="…$<key>_field$<control>"`, so never paste full ASP.NET names.

## Resilience

Municipalities edit their e-services. The submitter tolerates small changes and reports the rest as drift instead of sending a broken form.

- **Fields**: exact `key` + `control` first, then the same `key` with the same kind of input, then a control of the same `type` (`select`, `radio`, `text`, `textarea`, `hidden`, `checkbox`) or `control` class under a question whose label matches one of `labels` (`{"sv": ["Beskriv felet här"], "en": […]}`). Labels compare case- and diacritic-insensitively and ignore `*`, a trailing `:` and extra spaces.
- **Options** (dropdowns, radios): exact value, then the visible text or value after the same normalisation, then `categories[].synonyms` or the field's `optionSynonyms` (`{"Ja": ["Ja tack"]}`, keyed by `yesValue`/`noValue`).
- **Pages**: by `PageId`, or, if the id was renamed, by finding all of a page's fields on it. Pages without fields (the summary) are matched by id only.
- **Drift**: anything else throws `SubmissionError.formChanged(FormDrift)` with `pageID`, `missing` (labels of fields or options Fixa can't fill, and of new required questions, the ones with a visible `*`) and a one-sentence `detail`. Network and server answers stay `transport`, `http`, `sessionLocked` and `serverValidation`.

`fixa-cli dry-run` exits 2 on drift (1 on any other failure), so a scheduled CI job can tell "the form changed" from "the site was down". When it fires, capture the new page, add the new texts to `labels`/`synonyms` or update `key`, and add a fixture test.

## When a municipality changes its form

The app downloads `adapters/<id>.json` and `adapters/status.json` from `main` on GitHub (raw.githubusercontent.com) at launch and when it becomes active, at most every 6 hours. A downloaded adapter replaces the bundled one only if it decodes, passes the same consistency checks as the bundled copy (`AdapterSpec.problems`), has the same `id`, a `specVersion` the app supports, and a `minAppBuild` no higher than the installed build. Otherwise the app keeps what it has. A fix that only needs JSON therefore needs no App Store release.

1. **Canary.** `.github/workflows/canary.yml` runs `fixa-cli dry-run` every day at 06:17 UTC, on every push touching `adapters/**` or `FixaKit/**`, and on demand. Exit 2 (form changed) sets the adapter's state in `adapters/status.json` to `degraded` with a kind message in English and Swedish, and opens (or comments on) an issue labelled `canary` with the drift report. Exit 1 (site down, build broken) only opens or updates the issue.
2. **Users.** Apps pick up the `degraded` status within 6 hours and show the message on Home. Reports stay saved and can still go by e-mail.
3. **Fix.** Read the drift report in the issue, run `swift run fixa-cli dry-run --save-html page.html` locally, then update `key`, `labels` or `synonyms` in `adapters/<id>.json`, copy it into `FixaKit/Sources/FixaKit/Resources/adapters/`, and add a fixture test.
4. **Push** to `main`. The canary runs on the push; when the dry run passes it sets the status back to `ok` and closes the issue. Apps pick up the new adapter and status within 6 hours.

Bump `minAppBuild` only when the adapter needs an engine change (a new field role, a new channel kind). Then ship the new build first; older builds keep their bundled adapter and keep showing the status message. Set `state` to `down` by hand in `status.json` if the e-service is off entirely.

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
