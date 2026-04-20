# Archive Session Data With Plan

## Restructure archive format — fb6cf27
- [x] Change archive from flat files to per-plan folders (`.flow/archive/<plan-name>/`)
- [x] Move task file into the subfolder
- [x] Handle collision with timestamp suffix on the folder name

## Capture and archive session entry — fb6cf27
- [x] Capture session JSON (via `--get-json`) before `--remove` deletes it
- [x] Write `session.json` into the archive subfolder (session ID + entry fields + archived timestamp)
- [x] Reorder: capture → archive → remove (currently remove happens first)

## Update output — fb6cf27
- [x] Update echo messages to report the folder path instead of a file path
