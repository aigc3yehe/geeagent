# Local Project Manager

Local Project Manager is a first-party native Gear for saving local project
launch commands and controlling their running services.

Project records are stored under:

```text
~/Library/Application Support/GeeAgent/gear-data/local.project.manager/projects.json
```

The Gear checks running state in this order:

- reachable configured frontend port listener
- Gear-managed launch PID from a command started in this surface
- command fingerprint match from the saved shell command

Clicking the project tile starts a stopped service or stops a running one. Edit
and remove remain separate controls on the tile. Running projects with a saved
frontend port show an Open Page control that opens the configured localhost URL.

Deleting a project button removes only the saved Gear configuration. It does
not delete the project directory or source files.
