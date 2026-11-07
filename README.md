# Moko

A pixel character that lives in your Mac's menu bar, gets more bloodshot the longer you stare at your screen, and then takes the screen over until you rest your eyes.

![The characters and the bloodshot ramp](docs/characters.png)

- **Every 20 minutes:** look at something far away for 20 seconds.
- **Every hour:** go for a walk. The screen stays blocked for 2 minutes.
- **Characters:** a bloodshot eyeball or an onion. Pick one from the menu.

## Install

You need macOS 13 or newer and the Xcode command line tools.

```bash
git clone https://github.com/termvato/moko.git
cd moko
./build.sh
open Moko.app
```

The build is ad-hoc signed, so it runs on the Mac that built it. To share a ready-made app, you'd need to sign and notarize it with an Apple Developer ID.

New menu bar icons appear next to the notch. To move the icon, hold ⌘ and drag it.

## Getting out

You get a 10-second warning first: Moko peeks up from the bottom of the screen and slowly grows while you keep working, with a countdown at the top. Input only locks when it reaches full size and stomps.

A blocking app shouldn't be able to trap you, so there are several ways out of a takeover:

- Hold **Esc** for 3 seconds to skip the break.
- Click **later** to snooze it (5 min for eyes, 10 min for walks).
- A watchdog timer force-closes the overlay 10 seconds after the break should have ended.
- Force Quit is never disabled.

To turn blocking off, untick **take over the screen** in the menu. You'll get a small popup instead.

## Good manners

- **Calls:** if any mic or camera is in use, you get the small popup rather than a takeover. It only reads whether devices are running, so it never opens them or asks for permission.
- **Time away:** after 5 minutes with no input, or when the Mac wakes from sleep, the timers reset. You already had your break.
- **Videos:** a playing video keeps the timers running even with no input, since your eyes are still on the screen. Calls and screen sharing count the same way.
- **Privacy:** no network access, analytics, or accounts.

## Changing the timing

The numbers are at the top of [`Sources/main.swift`](Sources/main.swift). Change them and rerun `./build.sh`.

To try a break without waiting:

```bash
MOKO_EYE_SECONDS=3 Moko.app/Contents/MacOS/Moko --eye-now
```

`--walk-now` does the same for a walk, and blocks the screen for the full 2 minutes unless you bail.

## Does this actually help?

Somewhat, and the evidence is modest.

- **Eye breaks:** in a study of 29 symptomatic computer users, 20-20-20 reminders reduced eye strain and dry eye symptoms, but the benefit was gone a week after the reminders stopped. It had no control group, and the rule's exact numbers aren't well established. ([Talens-Estarelles et al.](https://research.aston.ac.uk/en/publications/the-effects-of-breaks-on-digital-eye-strain-dry-eye-and-binocular/))
- **Walking breaks:** a meta-analysis of short lab trials found light walking breaks lower blood sugar after meals better than standing breaks. ([Buffey et al., 2022](https://link.springer.com/article/10.1007/s40279-022-01649-4))
- **How often:** in a small trial of 11 adults, only 5 minutes every 30 minutes significantly reduced the glucose rise, while all break schedules, including hourly, lowered blood pressure. ([Duran et al., 2023](https://sedentarybehaviour.org/2023/05/31/breaking-up-prolonged-sitting-to-improve-cardiometabolic-risk-dose-response-analysis-of-a-randomized-crossover-trial))

## License

[MIT](LICENSE)
