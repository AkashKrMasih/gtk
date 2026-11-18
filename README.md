# Rsync Paste (GTK)

Small Ruby + GTK 3 desktop app: stage files and folders, then paste them into a folder you pick using **rsync** (`-a`, progress on stderr).

## Requirements

- Ruby 3.x
- `rsync` on your PATH (default `/usr/bin/rsync`)
- GTK 3 development libraries (for the `gtk3` gem)

On Debian/Ubuntu — for the **gtk3** gem (default in `Gemfile`):

```bash
sudo apt install libgtk-4-dev libgirepository1.0-dev rsync

```

If `bundle install` fails to compile native extensions, switch to **GirFFI** bindings (runtime libraries only). In `Gemfile`, comment `gtk3` and uncomment `gir_ffi-gtk`, then:

```bash
sudo apt install rsync gir1.2-gtk-3.0 libharfbuzz-gobject0 gobject-introspection
gem install gir_ffi-gtk   # or bundle install
```

## Setup

```bash
cd ~/rsync-paste-gtk
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