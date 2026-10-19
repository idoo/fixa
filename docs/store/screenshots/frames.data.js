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
    id: "02", screen: "review", purpose: "proof",
    desire: "Show them exactly what and where, without describing the spot in words.",
    objection: "They will never find the place from my description.",
    proof: "Review: category, map with pin at Gustavsberg centrum, description and the photo, under 'This is what Värmdö kommun receives'.",
    evidence: ["Fixa/Screens/ReviewScreen.swift", "Fixa/Screens/LocationPickerSheet.swift", "captures/*/review.png"],
    background: { from: "#F7F5F0", to: "#E1ECE3", glow: "#CFE3D3" },
    headline: { "sv": "Ta en bild, sätt nålen", "en-US": "Snap a photo, drop a pin" },
    subline: { "sv": "Du ser precis vad kommunen får.", "en-US": "See exactly what the municipality gets." },
    pops: [],
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
    // Stamp measured by colour bbox (orange 705x322 at 308,781 sv / 308,814 en) plus padding.
    pops: [{
      src: "receipt",
      crop: { "sv": { x: 270, y: 751, w: 780, h: 382 }, "en-US": { x: 270, y: 784, w: 780, h: 382 } },
      scale: 1.36, center: { x: 660, y: 1340 }, radius: 44, rotate: 0,
    }],
  },
  {
    id: "04", screen: "profile", purpose: "objection: account and privacy",
    desire: "Report without signing up or handing over my details.",
    objection: "Another app that wants an account and my data.",
    proof: "Profile: 'Optional. Only used when you ask for a reply. Saved on this phone.'",
    evidence: ["Fixa/Screens/ProfileScreen.swift:21", "Fixa/Screens/AboutScreen.swift:20 no account, no server"],
    background: { from: "#F7F5F0", to: "#E4E7F0", glow: "#D3D9EA" },
    headline: { "sv": "Inget konto behövs", "en-US": "No account needed" },
    subline: {
      "sv": "Uppgifterna stannar i telefonen. Fyll i dem bara om du vill ha svar.",
      "en-US": "Your details stay on your phone. Add them only if you want a reply.",
    },
    // Caption block under the nav bar (text rows 380..524, both locales two lines).
    pops: [{
      src: "profile",
      crop: { "sv": { x: 24, y: 362, w: 1272, h: 182 }, "en-US": { x: 24, y: 362, w: 1272, h: 182 } },
      scale: 0.9, center: { x: 660, y: 2330 }, radius: 40, rotate: 0,
    }],
  },
  {
    id: "05", screen: "about", purpose: "objection: trust",
    desire: "Trust who is behind it.",
    objection: "Is this official? Who made it and what do they do with my report?",
    proof: "About: 'Open source (EUPL-1.2) on GitHub', 'No account, no server', 'Independent app, not part of Värmdö kommun.' App icon.",
    evidence: ["Fixa/Screens/AboutScreen.swift:15-24", "docs/store/metadata.json description: 'Jag bor själv i Värmdö'"],
    background: { from: "#F7F5F0", to: "#EFE6D8", glow: "#E6D6BF" },
    headline: { "sv": "Fristående och öppen källkod", "en-US": "Independent and open source" },
    subline: { "sv": "Byggd av en invånare i Värmdö. Inte kommunens app.", "en-US": "Built by a Värmdö resident. Not the municipality's app." },
    // White card measured by pixel scan: x 51..1268, y 375..993 (sv) / 375..932 (en).
    pops: [{
      src: "about",
      crop: { "sv": { x: 51, y: 375, w: 1218, h: 619 }, "en-US": { x: 51, y: 375, w: 1218, h: 558 } },
      scale: 0.95, center: { x: 660, y: 1500 }, radius: 46, rotate: 0,
    }],
    icon: { src: "../../../Fixa/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png", size: 300, center: { x: 660, y: 2180 } },
  },
];
