# Agent Runtime Bridge

This app is the first GeeAgent runtime bridge for the official agent SDK.

Phase 1 responsibilities:

- own a long-lived SDK session per GeeAgent conversation
- accept JSON-line commands over `stdin`
- emit JSON-line runtime events over `stdout`
- translate SDK permission pauses into host-visible approval requests
- keep GeeAgent host outside the raw SDK loop

This bridge is intentionally narrow.

It is not:

- the GeeAgent product shell
- the GeeAgent approval UI
- the GeeAgent persona system
- a provider-neutral runtime

`Xenodia` remains outside this bridge as a separate host-owned lane.
