# Welcome window messages

MacTerm+ shows a **Welcome** window on first launch, after each update, and whenever there is a message
the user hasn't seen yet (users can turn this off). Its messages come from
[`announcements.json`](../announcements.json) on the `main` branch of this repository, so you can change
them at any time by editing that file on GitHub. No app release is needed; apps pick it up the next time they open.

## Format

```json
{
  "version": 1,
  "messages": [
    {
      "id": "spring-sale-2027",          // unique; change it to show a message again
      "title": "Headline",
      "body": "Text with **bold**, *italic* and [links](https://example.com).",
      "style": "info",                   // info | news | tip | warning | ad ("ad" shows a "Sponsored" label)
      "imageURL": "https://…/banner.png",// optional, https only, shown above the text (about 560×140)
      "buttonTitle": "Learn more",       // optional
      "buttonURL": "https://…",          // optional, https only, opens in the browser
      "start": "2027-03-01",             // optional (UTC dates)
      "end": "2027-03-31",               // optional, last day it shows
      "minVersion": "1.0.0",             // optional: only these app versions
      "maxVersion": "1.9.9",
      "priority": 10                     // optional: higher shows first
    }
  ]
}
```

(Comments above are for explanation only; JSON files can't contain comments.)

## Tips

- Keep the file valid JSON. If it can't be read, the app keeps showing the last good copy.
- Only `https://` images and links are used.
- A message counts as "seen" once the window has shown it; publish a new `id` to bring the window up again.
- Messages are cached, so they also show when the Mac is offline.
