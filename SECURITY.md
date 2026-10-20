# Security

## Reporting a vulnerability

Please report security problems privately through GitHub: open [github.com/idoo/fixa/security/advisories/new](https://github.com/idoo/fixa/security/advisories/new) ("Report a vulnerability"). Don't open a public issue for them. You'll get an answer within a week. Please don't test against the municipality's live e-service: every report sent there becomes a real case. The fixtures in `FixaKit/Tests/FixaKitTests/Fixtures` and `fixa-cli dry-run` (stops at the summary page, nothing is sent) are enough to reproduce most things.

## What the app sends where

There is no Fixa server. The app talks to three places:

| Destination | What | When |
|---|---|---|
| The municipality's e-service (today `https://service.varmdo.se`, Abou) | Problem type, description, place, one photo and, if you ask for a reply, name, e-mail and phone | When you press Send |
| `https://raw.githubusercontent.com/idoo/fixa/main/adapters/` | Nothing about you; a plain download of the adapter JSON and `status.json` | At most every 6 hours |
| Apple Maps | Map tiles, address search, the pin's address | While you place the pin |

If you choose the e-mail fallback, your own Mail app sends the report to the municipality's address in the bundled adapter.

## Adapter updates

The downloaded adapter describes the municipality's form, so it is treated as untrusted. The app accepts it only when:

- its id matches an adapter bundled in the app, and its channel kind, host, service, fallback e-mail and emergency phone numbers match that bundled adapter;
- `baseURL` is a plain `https://host` with no user, port, path or query, and every path starts with a single `/`, with no scheme, `//`, `:` or backslash;
- it is at most 256 KB and within the page, field and list limits in `AdapterSpecValidator`.

Anything else is ignored and logged, and the app keeps the bundled or last accepted adapter. The download uses an ephemeral session without cookies or cache, and only from the URL above.

## On the phone

The e-service session cookie lives in a per-report ephemeral session and is never written to disk. Photos are re-encoded (no EXIF or GPS). Draft photos are stored with complete file protection and excluded from backups.
