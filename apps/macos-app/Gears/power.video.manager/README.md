# Power Video Manager

Read-only native Gear for inspecting AI video production run folders.

The Gear opens a user-selected `runs` workspace, discovers child folders with
`script/script-archive.md`, and displays project metadata, production assets,
shot timelines, edit renders, final videos, selected-version markers, and
lightweight cost evidence when present.

Video assets render poster thumbnails from the file itself and switch to muted
looping playback while the pointer hovers over a video tile.

This first version does not generate assets, review candidates, expose root-agent
capabilities, or write back into the selected workspace.
