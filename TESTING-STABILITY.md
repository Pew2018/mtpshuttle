# Stability Fix Test Checklist

Test branch: `fix/test-stability-suite`

## CI build

- [ ] GitHub Actions Swift tests pass.
- [ ] GitHub Actions arm64 macOS app build passes.
- [ ] App bundle and downloadable ZIP checks pass.
- [ ] Download and launch the ZIP-built app on an Apple Silicon Mac.
- [ ] Record macOS version and app build number.

## Android → Finder export

Use a connected Android device and Finder as the destination.

- [ ] Drag one small text file from Android to Finder.
- [ ] Drag one image and one larger file (for example, a video) to Finder.
- [ ] Drag multiple selected files of mixed types in one operation.
- [ ] Drag a folder containing nested files to Finder, if the Android browser exposes folders as draggable entries.
- [ ] Confirm Finder remains responsive, each promised file has the expected name and contents, and failed/cancelled exports report an error without leaving partial files behind.
- [ ] Repeat the earlier symptom path and record whether Finder or MTP Shuttle hangs or exits unexpectedly.

Record tested file types, file sizes, number of items, and outcome:

## App internal two-pane drag

- [ ] Drag Android items to the Mac pane and verify the intended copy/move behavior.
- [ ] Drag Mac files/folders to the Android pane and verify the intended copy/move behavior.
- [ ] Confirm selection, single-click, double-click, and context menus remain usable.

## Finder → Android folder move integrity

Prepare a Finder folder with a hidden file (such as `.audit-hidden`), a nested folder with a file, and an empty nested folder.

- [ ] Copy the folder to Android and confirm every visible/hidden file and empty directory appears.
- [ ] Move the folder to Android and confirm the source folder is removed only after the complete destination contents are verified.
- [ ] Interrupt an upload, cancel it, or disconnect the device during transfer; confirm the Finder source remains.
- [ ] Cause destination verification to fail (for example, disconnect before verification); confirm the Finder source remains and the app reports failure.
- [ ] If Android/MTP omits hidden files or empty folders from browse results, confirm the conservative verification failure keeps the Finder source.

Record device model, Android version, folder contents, and outcomes:

## Duplicate basenames in one Finder drop

Use two different local folders containing files with the same basename, then drop both files together onto an initially empty Android directory.

- [ ] Confirm the app detects the in-batch collision before transfer.
- [ ] Choose rename and confirm both files arrive with distinct names and the extension is preserved.
- [ ] Repeat with an existing same-name Android item; confirm rename avoids every existing and in-batch name.
- [ ] Choose overwrite and confirm only the existing destination item is replaced while the second batch item gets a unique name.
- [ ] Choose cancel and confirm neither source is transferred or deleted.

Record selected conflict action and outcomes:

## Completion notes

- Finder real-device drag-out: **not yet tested**
- Android folder move integrity: **not yet tested**
- Duplicate-name transfers on device: **not yet tested**
- CI/unit tests passing do not establish these real-device scenarios.
