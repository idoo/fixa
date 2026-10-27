// Fixa App Store gallery: brief, copy, crops and colours. Edit this file, not the renderer.
// Coordinates are canvas px (1320x2868). Capture crops are source px of the raw 1320x2868 captures.
// Raw captures: captures/<locale>/<screen>.png, made by capture.sh.

window.GALLERY = {
  canvas: { width: 1320, height: 2868, scale: 1, colorSpace: "srgb" },
  safeArea: { top: 120, right: 80, bottom: 60, left: 80 },
  captureSize: { width: 1320, height: 2868 },
  locales: ["sv", "en-US"],
  headline: { minPx: 110, maxLines: 2 },

  // Product brief (evidence: docs/store/metadata.json, Fixa/Screens/*.swift).
  audience: "Residents of Värmdö who just walked past a dark street light, a pothole or graffiti and think 'someone should report that'.",
  desiredProgress: "Get it fixed without hunting for the right form, and know it actually arrived.",
  alternative: "The municipality's web form on a phone: long, fiddly, easy to give up halfway; or doing nothing.",
  promise: "Pick the problem, take a photo, drop a pin, send. The case number comes back in the app.",
  differentiator: "It files into the municipality's own e-service queue and shows the case number at once; no account.",
  objection: "Is this some unofficial thing that wants my data? It is independent, open source, has no account, and keeps details on the phone.",
};

// Device: the same box on every frame (continuity). Rounded corners + hairline, no bezel.
window.DEVICE = { x: 170, y: 650, w: 980, radius: 132 };

// Copy shapes: headline 2 to 6 words, subline optional. No em or en dashes.
window.FRAMES = [
  {
    id: "01", screen: "home", purpose: "hook",
    desire: "Report the thing I just saw before I forget it.",
    objection: "Reporting to the municipality is a chore.",
    proof: "Home: big category buttons, 'Report a problem in Värmdö in a minute'.",
    evidence: ["Fixa/Screens/HomeScreen.swift", "captures/*/home.png"],
    background: { from: "#F7F5F0", to: "#DFE9F2", glow: "#C9DCEC" },
    headline: { "sv": "Anmäl ett fel på en minut", "en-US": "Report a problem in a minute" },
    subline: { "sv": "Gatlampa släckt? Tryck, fota, skicka.", "en-US": "Street light out? Tap, snap, send." },
    pops: [],
  },
  {
    id: "02", screen: "location", purpose: "proof",
    desire: "Show them exactly where, without describing the spot in words.",
    objection: "They will never find the place from my description.",
    proof: "Location picker: map with the centre pin and the address under it, plus a big 'Use my current location' button.",
    evidence: ["Fixa/Screens/LocationPickerSheet.swift", "captures/*/location.png"],
    background: { from: "#F7F5F0", to: "#E1ECE3", glow: "#CFE3D3" },
    headline: { "sv": "Sätt nålen på kartan", "en-US": "Drop a pin on the map" },
    subline: { "sv": "Eller tryck på Använd min nuvarande plats.", "en-US": "Or just tap Use my current location." },
    // Button outline measured on the capture: x 48..1272, y 616..788 (both locales).
    pops: [{
      src: "location",
      crop: { "sv": { x: 48, y: 616, w: 1224, h: 172 }, "en-US": { x: 48, y: 616, w: 1224, h: 172 } },
      scale: 0.94, radius: 30, rotate: 0,
    }],
  },
  {
    id: "03", screen: "receipt", purpose: "differentiator",
    desire: "Know it arrived, with something to refer to later.",
    objection: "Reports vanish into a black hole.",
    proof: "Receipt: orange 'MOTTAGET' stamp with the case number, 'Sent to Värmdö kommun', Copy case number.",
    evidence: ["Fixa/Screens/ReceiptScreen.swift", "Fixa/DesignSystem/FxStatusStamp.swift", "Fixa/Screens/HistoryScreen.swift case number kept in history"],
    background: { from: "#F7F5F0", to: "#F4E3D5", glow: "#F2D3BE" },
    headline: { "sv": "Ärendenummer direkt", "en-US": "Your case number, right away" },
    subline: { "sv": "Det sparas i appen, så du kan följa upp.", "en-US": "It stays in the app so you can follow up." },
    // Stamp measured by colour bbox (orange 705x322 at 308,781 sv / 308,730 en) plus outline padding.
    pops: [{
      src: "receipt",
      crop: { "sv": { x: 280, y: 766, w: 760, h: 352 }, "en-US": { x: 280, y: 715, w: 760, h: 352 } },
      scale: 1.15, radius: 44, rotate: 0,
    }],
  },
  {
    id: "04", screen: "privacy", purpose: "objection: account and privacy",
    desire: "Report without signing up or handing over my details.",
    objection: "Another app that wants an account and my data.",
    proof: "'What Fixa stores': every item kept on this phone until you delete it; 'Fixa has no account, server or statistics.'",
    evidence: ["Fixa/Screens/PrivacyScreen (FixaScreen privacy)", "Fixa/Screens/SettingsScreen.swift:154-168 Delete all data"],
    background: { from: "#F7F5F0", to: "#E4E7F0", glow: "#D3D9EA" },
    headline: { "sv": "Inget konto behövs", "en-US": "No account needed" },
    subline: {
      "sv": "Dina uppgifter stannar i telefonen. Radera dem när du vill.",
      "en-US": "Your details stay on your phone. Delete them anytime.",
    },
    // "No account" row inside its card, measured: card top 1594, row separator 1893 (sv) / 1833 (en).
    pops: [{
      src: "privacy",
      crop: { "sv": { x: 48, y: 1594, w: 1224, h: 290 }, "en-US": { x: 48, y: 1594, w: 1224, h: 230 } },
      scale: 0.94, radius: 40, rotate: 0,
    }],
  },
  {
    id: "05", screen: "language", purpose: "objection: will it work for me",
    desire: "Use it in the language I read best.",
    objection: "My Swedish is not good enough for a municipal form.",
    proof: "Language screen: English, Svenska, Suomi, العربية, Українська, Polski; switches immediately.",
    evidence: ["Fixa/Screens/SettingsLanguageScreen.swift:32 'buttons and texts change now'", "captures/*/language.png"],
    background: { from: "#F7F5F0", to: "#EFE6D8", glow: "#E6D6BF" },
    headline: { "sv": "Fixa på 22 språk", "en-US": "Fixa in 22 languages" },
    subline: { "sv": "Byt språk direkt i appen.", "en-US": "Switch language right in the app." },
    pops: [],
  },
];
