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
    // Inside of the button's 6 px outline, measured on the build 12 captures (both locales):
    // outline x 37..42 / 1278..1283, y 600..605 / 762..767; inner corner radius about 50 px.
    pops: [{
      src: "location",
      crop: { "sv": { x: 43, y: 606, w: 1235, h: 156 }, "en-US": { x: 43, y: 606, w: 1235, h: 156 } },
      scale: 0.93, radius: 46, rotate: 0,
    }],
  },
  {
    id: "03", screen: "receipt", purpose: "differentiator",
    desire: "Know it arrived, with something to refer to later.",
    objection: "Reports vanish into a black hole.",
    proof: "Receipt: orange 'MOTTAGET'/'RECEIVED' stamp with the case number, 'Sent to Värmdö kommun', Copy case number, and the kommun's own receipt text (outside a Swedish UI translated, with 'Show original').",
    evidence: [
      "Fixa/Screens/ReceiptScreen.swift:111 FxStatusStamp, :136 Copy case number, :165-183 kommunReceipt",
      "Fixa/Screens/KommunTextView.swift:79-82 translated with 'Show original'; Swedish UI shows the Swedish",
      "Fixa/Services/HistoryStore.swift:83-87 case number and receipt text kept in Sent reports",
      "captures/*/receipt.png",
    ],
    background: { from: "#F7F5F0", to: "#F4E3D5", glow: "#F2D3BE" },
    headline: { "sv": "Ärendenummer direkt", "en-US": "Your case number, right away" },
    subline: { "sv": "Kommunens eget kvitto sparas i appen.", "en-US": "The kommun's own receipt stays in the app." },
    // Stamp bbox incl. outline and shadow (non-background pixels, y 150..650): sv 303..1017 x 250..583,
    // en-US 323..996 x 252..581; one crop centred on both with 16 px margin. Scale 1.0 keeps the pop
    // between the status bar (ends ~769 canvas) and the 'Sent to' title (~1178 canvas).
    pops: [{
      src: "receipt",
      crop: { "sv": { x: 287, y: 234, w: 746, h: 366 }, "en-US": { x: 287, y: 234, w: 746, h: 366 } },
      scale: 1.0, radius: 40, rotate: 0,
    }],
  },
  {
    id: "04", screen: "privacy", purpose: "objection: account and privacy",
    desire: "Report without signing up or handing over my details.",
    objection: "Another app that wants an account and my data.",
    proof: "'What Fixa stores', four lines with icons; first: 'Your details, drafts and sent reports stay on this phone. No account, no tracking.'; last: 'Delete everything in Settings.'",
    evidence: ["Fixa/Screens/PrivacyScreen.swift (FixaScreen privacy)", "captures/*/privacy.png"],
    background: { from: "#F7F5F0", to: "#E4E7F0", glow: "#D3D9EA" },
    headline: { "sv": "Inget konto behövs", "en-US": "No account needed" },
    subline: {
      "sv": "Dina uppgifter stannar i telefonen. Radera dem när du vill.",
      "en-US": "Your details stay on your phone. Delete them anytime.",
    },
    // First line of the card, measured: card inside x 51..1268 from y 384 to the first separator
    // (sv 649, en-US 588).
    pops: [{
      src: "privacy",
      crop: { "sv": { x: 51, y: 384, w: 1218, h: 265 }, "en-US": { x: 51, y: 384, w: 1218, h: 204 } },
      scale: 0.93, radius: 40, rotate: 0,
    }],
  },
  {
    // Swedish UI shows the kommun's Swedish as is, so the sv frame uses a Finnish-UI receipt;
    // en-US uses the English one (capture.sh writes both as receipt-translated.png).
    id: "05", screen: "receipt-translated", purpose: "differentiator: language",
    desire: "Use it in the language I read best.",
    objection: "My Swedish is not good enough for a municipal form.",
    proof: "Receipt in Finnish (sv) / English (en-US): the kommun's Swedish receipt shown translated, 'Translated from Swedish', 'Show original'; 'What you wrote' with 'Filed in Swedish'.",
    evidence: [
      "Fixa/Screens/KommunTextView.swift:79-82,165-180 translated receipt with 'Show original'",
      "Fixa/Screens/ReviewScreen.swift:219 'Translating your text into Swedish…'",
      "Fixa/Screens/ReceiptScreen.swift:146-148 the kommun's e-mail reply stays Swedish (so: receipt, not reply)",
      "captures/*/receipt-translated.png",
    ],
    background: { from: "#F7F5F0", to: "#EFE6D8", glow: "#E6D6BF" },
    headline: { "sv": "Skriv på ditt språk", "en-US": "Write in your own language" },
    subline: {
      "sv": "Fixa översätter till svenska. Kommunens kvitto visas på ditt språk.",
      "en-US": "Fixa translates it into Swedish. The kommun's receipt shows in yours.",
    },
    // The kommun-receipt card, measured inside: x 51..1268, y 1098..2085 (both captures).
    pops: [{
      src: "receipt-translated",
      crop: { "sv": { x: 51, y: 1098, w: 1218, h: 988 }, "en-US": { x: 51, y: 1098, w: 1218, h: 988 } },
      scale: 0.93, radius: 40, rotate: 0,
    }],
  },
];
