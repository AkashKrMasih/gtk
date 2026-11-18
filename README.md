# Rsync Paste (GTK 4)

Small Ruby + GTK 4 desktop app: stage files and folders, then paste them into a folder you pick using **rsync** (`-a`, with live progress).

## Requirements

- Ubuntu 24.04 (GTK 4.14) or any distro with GTK 4.10+
- Ruby 3.x
- `rsync` on your PATH (default `/usr/bin/rsync`)
- GTK 4 development libraries (for the `gtk4` gem)

On Debian/Ubuntu:

```bash
sudo apt install ruby ruby-dev build-essential libgtk-4-dev libgirepository1.0-dev rsync
```

If `bundle install` or `gem install` fails while compiling a native extension, install the `-dev` package named in the error message and try again.

## Setup

The `Gemfile` should contain:

```ruby
source 'https://rubygems.org'

gem 'gtk4'
```

Then install:

```bash
cd ~/rsync-paste-gtk
bundle install
```

Without bundler you can instead run `gem install gtk4`.

## Run

```bash
bundle exec ruby app.rb
```

or, if you installed the gem globally:

```bash
ruby app.rb
```

## Usage

1. Leave **App is ON** enabled (the toggle turns paste off).
2. **Copy…** — pick one or more files or folders to stage.
3. **Paste to…** — choose the destination directory; each staged path is copied with rsync into that folder (names preserved).
4. Watch the log and progress bar while rsync runs.
5. **Clear staging** empties the staged list.

## Configuration

Set `RSYNC` if rsync is not at `/usr/bin/rsync`:

```bash
RSYNC=/usr/local/bin/rsync ruby app.rb
```

## Notes

- This version targets **GTK 4 only**. The GTK 3 (`gtk3`) and GirFFI fallbacks were removed.
- rsync runs as `rsync -a --human-readable --info=progress2 --no-inc-recursive -- <source> <destination>/`. Progress is read from rsync's combined output, so the progress bar and log update while it runs.
- `--delete` is supported by `RsyncCopier.copy_all(..., delete: true)` but is **not** exposed in the UI, because it removes files in the destination that are not in the source.

## Troubleshooting

- **Bundler prints `already initialized constant Gem::Platform::...` warnings:** these come from a bundler/RubyGems version mismatch, not from the app. Run `ruby app.rb` without bundler, or use a bundler version that matches your RubyGems.
- **Blank or missing widgets:** make sure you are running the GTK 4 `app.rb` (it uses `present`, not `show_all`) and that the `gtk4` gem, not `gtk3`, is loaded.
- **`cannot load such file -- gtk4`:** run `gem install gtk4`, or add it to the `Gemfile` and run `bundle install`.