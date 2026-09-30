# Changelog

Release notes for each version are on
[GitHub Releases](https://github.com/combinatrix-ai/until/releases). This file
collects what is ready for the next one.

## 1.2.0 (unreleased)

### New
- **Calendars on this Mac.** Until can show everything the Calendar app
  already syncs — iCloud, Google, Outlook/Exchange, CalDAV — without signing
  in. Mac calendars and Google accounts work side by side, and events that
  appear through both are merged.
- **Try it with a sample day.** The first-run popover can show a sample day
  before you connect a calendar.
- **Start alert.** Optionally put the meeting on screen as it starts, as a
  floating card or a full-screen takeover on every display, with Join, Snooze
  1 min, and Dismiss.
- **Join shortcut.** A global shortcut joins the meeting in the menubar, or
  the one that is running or about to start.
- **Desktop widgets** with today's agenda, in medium and large sizes.
- **Today at a glance.** The popover footer shows how many events are left,
  how much of the day is booked, and the longest free stretch.
- **Links from the invite.** The upcoming card shows up to three docs,
  designs, or pull requests linked from the event.

### Changed
- Meeting links from 30+ services are recognized, including Slack huddles,
  Discord, Jitsi, FaceTime, Amazon Chime, Gather, Tuple, Lark, and Tencent
  Meeting. Zoom and Teams links can open in their desktop apps.
- The menubar can show only the countdown, hiding the event title.
- Until runs natively on Intel Macs as well as Apple Silicon.
