# Rsync Paste (GTK)

Small Ruby + GTK 3 desktop app: stage files and folders, then paste them into a folder you pick using **rsync** (`-a`, progress on stderr).

## Requirements

- Ruby 3.x
- `rsync` on your PATH (default `/usr/bin/rsync`)
- GTK 3 development libraries (for the `gtk3` gem)

On Debian/Ubuntu:

```bash
sudo apt install rsync libgtk-3-dev
```

## Setup

```bash
cd rsync-paste-gtk
bundle install
```

## Run

```bash
bundle exec ruby app.rb
```

## Usage

1. Leave **App is ON** enabled (toggle turns paste off).
2. **Copy…** — pick one or more files or folders to stage.
3. **Paste to…** — choose the destination directory; each staged path is copied with rsync into that folder (names preserved).
4. Watch the log and progress bar while rsync runs.

Set `RSYNC` if rsync is not at `/usr/bin/rsync`.