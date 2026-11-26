# Terminal UI Redesign Reference

The updated design is based on the attached video and Android terminal UI references. The goal is to keep command execution as the primary surface while making controls available without covering the terminal.

| Element | Design decision |
|---|---|
| Terminal screen | Nearly black background, monospaced font, cyan cursor, and clear session status. |
| Command panel | Edge-aligned side panel opened by a small accessible `<` button; it is not permanently visible. |
| Status bar | Compact badges for PRoot, Arch, connection, and download state using green, amber, and cyan accents. |
| RootFS download | In-app notification showing stage, percentage, transferred size, speed, verification, and extraction. |
| Input | The input row stays close to the terminal and preserves space when the keyboard appears. |

References: the user-provided video, Termux interfaces shown on Google Play, and the UI update discussion in the Termux repository.
