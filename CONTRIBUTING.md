# Contributing to Until

Thanks for helping. Focused fixes, new meeting services, translations, and
documentation are all welcome.

## Build and run

Until is a plain SwiftPM package (Swift + SwiftUI/AppKit), no Xcode project.

```sh
swift build            # compile
swift test             # run the tests
scripts/dev.sh         # rebuild and relaunch as a real .app bundle
scripts/dev.sh --demo-mode   # the same, with a synthetic calendar
```

Mac calendars work without any setup. Google sign-in needs your own OAuth
desktop client:

1. In Google Cloud Console, create a project, enable the **Google Calendar
   API** (and the Drive and Docs APIs for meeting notes), and create an OAuth
   client ID of type **Desktop app**.
2. `cp .env.example .env` and fill in `GOOGLE_OAUTH_CLIENT_ID` and
   `GOOGLE_OAUTH_CLIENT_SECRET`. The packaging script bakes them into the app's
   `Info.plist`; `.env` is gitignored.

[AGENTS.md](AGENTS.md) has the full development notes: layout, demo mode for
screenshots, and the release and Mac App Store builds.

## Good first contributions

- **A meeting service Until doesn't recognize.** Add its domains to
  `EventLinks.MeetingProvider` in `Sources/Until/EventLinks.swift`, plus a test
  in `Tests/UntilTests/MeetingWorkflowTests.swift`.
- **A translation.** Strings live in `Sources/Until/Resources/<lang>.lproj/`;
  English keys double as the source text.

## Pull requests

Work on a branch and open a pull request against `main`. Please run
`swift test` and `swiftlint` before you push, and keep each pull request to one
change.
