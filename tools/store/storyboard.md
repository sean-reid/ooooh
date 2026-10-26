# App preview storyboard

24 seconds, portrait, 886 by 1920 at 30 fps, no voiceover, a silent stereo track. One caption per shot in Instrument Serif at the top, the same six beats as the screenshots. Every frame is a screen recording of the app on an iPhone 17 Pro Max simulator, dark, status bar at 9:41.

| Seconds    | On screen                                                                                        | Caption                                  |
| ---------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------- |
| 0 to 4     | The session screen: the orb listening, the clock ticking past 0:25.                              | Think out loud. It listens.              |
| 4 to 8     | The orb swells into its about-to-speak shape, then speaks, and the question appears beneath it.  | One question, when it matters.           |
| 8 to 12    | End is tapped and the notes screen comes up: title, decisions, insights, open threads.           | Your session, as notes.                  |
| 12 to 15.5 | The home screen on the next launch: the orb, Start, and the card of threads left open last time. | Pick up where you left off.              |
| 15.5 to 19 | The first-run screen "Think out loud." swipes to "It waits.", the page that explains quiet mode. | Quiet on the desk. Spoken on headphones. |
| 19 to 22.5 | The gear opens Settings: the listener switches, Subscribe, export, and delete.                   | Saved on your phone, yours to delete.    |
| 22.5 to 24 | Back on the home screen, the orb resting.                                                        | ooooh: Think Out Loud                    |

Poster frame: 6 seconds, the orb speaking under the second caption.

The simulator cannot play the spoken question into the recording, so the voice is absent from the file; the orb's speaking shape and the question text carry that beat. `preview.sh` cuts the clips `simctl io recordVideo` wrote to these times and burns the captions in.
