# Inline Terminal Images

The screen behaves as a real terminal: `kyroon_pty` connects the PRoot/Bash process to a PTY, and the local `xterm` parser handles ANSI data and paints cells. The image layer does not replace this path or turn the terminal into a text-printing component.

This release supports the **iTerm2 Inline Image** protocol through an `OSC 1337;File=...;inline=1:<base64>` frame. The decoder removes the image frame before passing the remaining stream to `xterm`, then displays a bounded preview above the terminal. Base64 data and image control sequences therefore do not enter the terminal buffer, copied text, or deep session transcript.

| Safety limit | Value | Purpose |
|---|---:|---|
| Maximum encoded payload | 2 MiB | Prevent large Base64 input from reaching memory or the UI |
| Maximum image dimensions | 2,000,000 pixels | Avoid decoding images that consume excessive memory |
| Retained previews | 2 | Limit concurrent images in the Flutter UI |
| Preview size | 220 × 220 points maximum | Prevent terminal coverage and expensive redraws |

Invalid or oversized frames are rejected and replaced with `[inline image rejected]`; their binary data is not retained. This release does not support SIXEL or Kitty Graphics. Those protocols require separate parsers and rendering paths, so the application does not claim to support them.

The behavioral performance test covers an encoded frame larger than 2 MiB and expects rejection within two seconds. This intentionally generous ceiling detects paths that might attempt to decode a large Base64 payload on the terminal UI thread.
