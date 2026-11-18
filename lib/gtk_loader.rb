# frozen_string_literal: true

module GtkLoader
  BINDING = begin
    require 'gtk3'
    :gtk3
  rescue LoadError
    require 'gir_ffi-gtk3'
    :gir_ffi
  end

  module_function

  def gtk3?
    BINDING == :gtk3
  end

  def accept?(response)
    sym = gtk3? ? response : Gtk::ResponseType.from_native(response)
    sym == :accept
  end

  # Returns array of paths or nil if cancelled.
  def choose_sources(parent, title: 'Select files or folders')
    dialog = build_open_dialog(parent, title)
    response = dialog.run
    return nil unless accept?(response)

    paths = dialog.filenames
    paths = paths.to_a unless paths.is_a?(Array)
    paths
  ensure
    dialog&.destroy
  end

  # Returns destination path or nil if cancelled.
  def choose_folder(parent, title: 'Choose destination folder')
    dialog = build_folder_dialog(parent, title)
    response = dialog.run
    return nil unless accept?(response)

    gtk3? ? dialog.filename : dialog.get_filename
  ensure
    dialog&.destroy
  end

  def build_open_dialog(parent, title)
    if gtk3?
      dialog = Gtk::FileChooserDialog.new(title: title, parent: parent, action: :open)
      dialog.select_multiple = true
      dialog.add_buttons(['Cancel', :cancel], ['Add', :accept])
    else
      dialog = Gtk::FileChooserDialog.new(title, parent, :open, [['Cancel', :cancel], ['Add', :accept]])
      dialog.select_multiple = true
    end
    dialog
  end

  def build_folder_dialog(parent, title)
    if gtk3?
      dialog = Gtk::FileChooserDialog.new(title: title, parent: parent, action: :select_folder)
      dialog.add_buttons(['Cancel', :cancel], ['Paste here', :accept])
    else
      dialog = Gtk::FileChooserDialog.new(
        title,
        parent,
        :select_folder,
        [['Cancel', :cancel], ['Paste here', :accept]]
      )
    end
    dialog
  end
end