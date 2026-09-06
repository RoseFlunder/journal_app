# Play Store Screenshot Usability Notes

Observed while staging the Android app on a Pixel 7 emulator at 1080 × 2400.
These are product observations only; no fixes have been applied yet.

## High priority

### New text blocks clip ordinary multi-line entries

- **Observed:** A newly inserted text block is only about two lines tall. Entering
  a short two-sentence reflection caused later lines to be clipped on the page.
- **Impact:** Users can lose sight of text they just entered and may assume it was
  not saved.
- **Suggested improvement:** Auto-grow text blocks while typing, with a sensible
  maximum width and minimum height. Keep all text visible when editing ends.

### Edit mode is difficult to discover after controls auto-hide

- **Observed:** Page controls disappear after a short idle period. A tap reveals
  them, then the user must find a separate Edit action near the top-right.
- **Impact:** A page can look read-only, especially to a first-time mobile user.
- **Suggested improvement:** Keep a persistent, clearly labeled Edit button or
  show a brief first-use hint such as “Tap Edit to add to this page.”

### Android keyboard dismissal and editor completion are ambiguous

- **Observed:** Text editing, hiding the keyboard, finishing an element edit, and
  leaving page editing use visually similar back/check interactions. The emulator
  keyboard's floating toolbar could remain over the app after text entry.
- **Impact:** Users may leave the editor or return home when they only intended to
  dismiss the keyboard.
- **Suggested improvement:** Provide an explicit “Done typing” action above the
  keyboard, keep “Finish page editing” visually distinct, and intercept Android
  Back in this order: dismiss keyboard → finish text editing → exit page editing.

## Medium priority

### Mobile editor toolbar relies almost entirely on icons

- **Observed:** Text, photo, sticker, more, layers, formatting, and completion are
  shown as icon-only actions on the phone layout.
- **Impact:** Several icons are ambiguous without desktop-style hover tooltips.
- **Suggested improvement:** Add short labels to the primary actions, or introduce
  a labeled expandable tool tray with Text, Photo, Sticker, Draw, and More.

### Navigation buttons cover the journal page

- **Observed:** Large previous/next buttons sit over the left and right edges of
  the paper at its vertical midpoint.
- **Impact:** They obscure content and compete visually with selected-object
  handles.
- **Suggested improvement:** Move navigation outside the paper, reduce its visual
  weight, or reveal it only after an edge tap/swipe.

### Selection handles overwhelm small elements

- **Observed:** The transform boundary and eight touch handles occupy much more
  space than a small text block.
- **Impact:** The selected content becomes difficult to read and precise movement
  feels visually noisy.
- **Suggested improvement:** Keep generous invisible hit targets but render
  smaller screen-space handles and a subtler selection boundary.

### Journal/page terminology is inconsistent

- **Observed:** The contents screen is titled “My Journals,” but each card and the
  nearby count represent a page, and the main action is “New page.”
- **Impact:** It is unclear whether users are creating multiple journals or pages
  inside one journal.
- **Suggested improvement:** Choose one mental model. For the current structure,
  “My Pages” or “Journal Pages” would match the count and creation action.

## Lower priority / polish

### Disabled cloud icon is unexplained

- **Observed:** A disabled cloud icon appears in the header when cloud sync is not
  configured, without visible explanatory text.
- **Impact:** It may look like an error or failed save state.
- **Suggested improvement:** Hide it until sync is available, or make it tappable
  with a clear “Cloud sync unavailable” explanation.

### Fit-page view leaves substantial unused vertical space

- **Observed:** On a tall Pixel 7 display, the finite A4 page is centered with a
  large empty band above it and editor controls below it.
- **Impact:** Journal content looks smaller than necessary in screenshots and
  during reading.
- **Suggested improvement:** Fit the page into the usable area below the top safe
  region and above controls, or remember a slightly larger comfortable reading
  zoom separately from the full-page overview.

### Delete is visually prominent on every contents card

- **Observed:** The delete icon is a primary visible action beside each page.
- **Impact:** It competes with opening the page and increases accidental-delete
  anxiety even if a confirmation follows.
- **Suggested improvement:** Move destructive actions into an overflow menu or
  swipe action while retaining confirmation and recovery where possible.

