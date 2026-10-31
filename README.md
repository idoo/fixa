<img src="Fixa/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="Fixa icon: two traffic cones on a wooden jetty">

# Fixa

**Report a problem in your municipality from your phone.** On the App Store as *Fixa: felanmälan till kommunen* (English: *Fixa: Report Local Problems*).

Fixa is an independent, open-source iPhone app for reporting everyday faults in your municipality: a street light that is out, a pothole, graffiti, a broken playground, a blocked drain in the street. You pick what's wrong, take a photo, drop a pin, and Fixa sends the report straight to the municipality's own e-service. Acute water and sewer faults are phoned in, not reported in the app.

**Fixa is not made by, endorsed by, or affiliated with any municipality.** It is a citizen-built tool that fills in the municipality's public web form for you, in a form that works better on a phone. Reports end up in the same queue as reports sent through the website.

The first supported municipality is Värmdö (Stockholm County). Adding another is a matter of writing one JSON file; see [docs/ADAPTERS.md](docs/ADAPTERS.md).

## Why

Fixa sends the same report to the same destination as Värmdö's own fault-report form, and adds:

- eight large tiles for the common cases, mapped to the form's categories;
- GPS, a real map and address search; coordinates go into both the place text and the form's map field;
- up to three photos, merged into the single attachment the form accepts, with metadata stripped;
- a one-tap call for acute water and sewer faults only, picking the right number for the time of day (service centre or the after-hours water/sewer duty line);
- other questions go to the municipality's own website: Fixa copies the case number and opens the contact page in an in-app Safari view;
- the interface in 22 languages: Swedish, English, Finnish, Arabic, Ukrainian, Russian, Polish, German, French, Spanish, Italian, Portuguese, Dutch, Danish, Norwegian, Estonian, Latvian, Lithuanian, Romanian, Greek, Hungarian and Czech;
- a local history of what you sent;
- Home Screen quick actions and Siri/Spotlight shortcuts to start a report for a problem or open Sent reports (an unsent report always comes first);
- when Fixa can't send (the form changed, a sign-in is required, or sending is paused), it copies the report text and opens the municipality's own web form instead.

## How it works

There is no Fixa server. The app talks directly to the municipality's e-service ([Abou](https://www.abou.se/) e-tjänsteplattform): it opens a fresh anonymous session, posts each page with the same fields the website sends (the photo goes to the form's own upload), presses *Slutför*, and reads the confirmation page. Everything about a municipality is described in an adapter file (`adapters/*.json`), validated by `schema/adapter.schema.json`: URLs, page IDs, field keys, categories, tiles, emergency numbers, opening hours and public holidays. No code change is needed.

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
cd FixaKit && swift test                         # package tests on macOS, offline (saved pages only)
```

`fixa-cli dry-run` walks the **live** e-service on the municipality's server up to the summary page (no photo, no case created, but the server sees the requests and keeps an unfinished session). Run it only by hand, after a user hit a changed form, to see what changed. Never in CI or on a schedule.

```sh
swift run --package-path FixaKit fixa-cli dry-run
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

- Nothing tests the live e-service automatically: Fixa sends the municipality no test traffic. If a send hits a changed form, it stops before the final step and offers the municipality's own web form; `adapters/status.json` is then set to `degraded` by hand.
- The app contacts GitHub only after a send has failed because the form changed: it then downloads the signed adapter and `status.json`, retries that send once if a newer adapter fixes it, and otherwise shows a calm banner: the report is saved and can still go in through the municipality's website. No checks on launch or on a timer.
- A fixed `adapters/*.json` reaches every phone without an App Store release, as long as this build accepts it.

## For Värmdö kommun

Fixa is an independent app by one developer; it is not run or approved by the kommun. Contact: [support@jvcr.se](mailto:support@jvcr.se).

- **What is sent.** Only what a resident chooses to send, when they press Send: the same fields the website form has (område, plats, map position, beskrivning, one photo, and name, phone and e-mail only when a reply is wanted). Nothing in a report names the app. One report is one walk through the form, about ten requests with a short pause between them.
- **How often.** Only when a resident sends. A phone sends at most 5 reports an hour and 15 a day, warns before a repeat report of the same problem within 14 days, and never re-sends a report whose final step may already have gone through.
- **No automatic traffic.** No test reports, no scheduled checks, no polling of the e-service. A failed send is retried a few times with growing pauses, honouring `Retry-After`.
- **Stopping Fixa.** If the kommun asks, we set Värmdö's state in `adapters/status.json` to `down`: installed apps then stop sending and point residents to the kommun's own web form. If the e-service answers 401/403 or asks for a sign-in, the app stops by itself and does the same. We don't work around blocks.
- **Questions from residents.** Fixa doesn't take them and doesn't phone or e-mail the kommun for them. "Questions about this report?" and "Other questions?" copy the case number and open the kommun's Kontaktcenter page (adapter `contact`) in an in-app Safari view; only acute water and sewer faults (VA-jouren / servicecenter during office hours) and 112 are calls. Questions about the app go to the developer, not the kommun.

## For other municipalities

You are free to take Fixa for your own municipality under the EUPL-1.2: point it at your e-service with one adapter file, put your own name, colours and icon on it, and publish it. If you'd like help adapting it, open an issue on [GitHub](https://github.com/idoo/fixa/issues).

## License

[EUPL-1.2](LICENSE).
