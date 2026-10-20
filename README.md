<img src="Fixa/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="Fixa icon: two traffic cones on a wooden jetty">

# Fixa

**Report a problem in your municipality without the e-service maze.** On the App Store as *Fixa: felanmälan till kommunen* (English: *Fixa: Report Local Problems*).

Fixa is an independent, open-source iPhone app for reporting everyday faults in your municipality: a street light that is out, a pothole, graffiti, a broken playground, a water leak. You pick what's wrong, take a photo, drop a pin, and Fixa sends the report straight to the municipality's own e-service.

**Fixa is not made by, endorsed by, or affiliated with any municipality.** It is a citizen-built tool that fills in the municipality's public web form for you, in a form that works better on a phone. Reports end up in the same queue as reports sent through the website.

The first supported municipality is Värmdö (Stockholm County). Adding another is a matter of writing one JSON file; see [docs/ADAPTERS.md](docs/ADAPTERS.md).

## Why

Värmdö's fault-report form is Swedish only, spans five web pages, accepts one attachment, and its map is blank: the tile server rejects requests because the site sends no `Referer`. Fixa keeps the same destination but adds:

- eight large tiles for the common cases, mapped to the form's categories;
- GPS, a real map and address search; coordinates go into both the place text and the form's map field;
- up to three photos, merged into the single attachment the form accepts, with metadata stripped;
- a one-tap emergency call that picks the right number for the time of day (service centre or the after-hours water/sewer duty line);
- the interface in 22 languages: Swedish, English, Finnish, Arabic, Ukrainian, Russian, Polish, German, French, Spanish, Italian, Portuguese, Dutch, Danish, Norwegian, Estonian, Latvian, Lithuanian, Romanian, Greek, Hungarian and Czech;
- a local history of what you sent;
- e-mail as a fallback when the e-service is down.

## How it works

There is no Fixa server. The app talks directly to the municipality's e-service ([Abou](https://www.abou.se/) e-tjänsteplattform): it opens a fresh anonymous session, uploads the photo, posts each page with the same fields a browser would send, presses *Slutför*, and reads the confirmation page. Everything about a municipality is described in an adapter file (`adapters/*.json`), validated by `schema/adapter.schema.json`: URLs, page IDs, field keys, categories, tiles, emergency numbers and opening hours. No code change is needed.

```
FixaKit/          Swift package: adapter spec, Abou client and parser, validation, tests, fixa-cli
Fixa/             SwiftUI app
adapters/         one JSON file per municipality e-service
schema/           JSON Schema for adapters
docs/ADAPTERS.md  how to add a municipality
```

## Build

Requirements: Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild test -scheme Fixa -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
cd FixaKit && swift test                         # package tests on macOS
swift run --package-path FixaKit fixa-cli dry-run # walks the live form up to the summary page, sends nothing
```

Signing settings in `project.yml` are the maintainer's; change `DEVELOPMENT_TEAM` and the bundle ID to build your own copy.

## Privacy

Fixa sends your report only to the municipality's e-service. Your e-mail, name and phone are stored only on your phone, and only while "Remember my details" is on. There is no analytics and no tracking. Details: [PRIVACY.md](PRIVACY.md).

### Settings & privacy

- Language (switches at once, right-to-left for Arabic), text size, appearance, bold text, higher contrast, reduce motion and vibration; each starts at the iPhone's own setting.
- "What Fixa stores" lists everything on the phone in plain words, with the file and key names.
- "Clear sent reports" and "Delete all my data" remove the history, the unsent report with its photos, and the contact details; display and language settings stay.
- A one-page first-launch note (independent app, where the report goes, call 112 in an emergency), reachable again from About › How Fixa works.

### If the municipality changes its form

- A daily canary (`.github/workflows/canary.yml`) dry-runs the e-service and opens an issue and marks the adapter `degraded` in `adapters/status.json` when the form no longer matches.
- The app reads `status.json` and the adapter from GitHub at most every six hours and shows a calm banner on Home: the report is saved and can still go by e-mail.
- A fixed `adapters/*.json` reaches every phone without an App Store release, as long as this build accepts it.

## For municipalities

You are free to take Fixa for your own municipality under the EUPL-1.2: point it at your e-service with one adapter file, put your own name, colours and icon on it, and publish it. If you'd like help adapting it, open an issue on [GitHub](https://github.com/idoo/fixa/issues).

## License

[EUPL-1.2](LICENSE).
