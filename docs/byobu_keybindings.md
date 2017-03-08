## byobu keybindings

byobu makes it easy to manage multiple terminal windows and panes. You can press `F1` to get help which includes a [list of keybindings](http://manpages.ubuntu.com/manpages/wily/en/man1/byobu.1.html#contenttoc8).

`C-` refers to the keyboard's `Control` key.
`M-` refers to the keyboard's `Meta` key which is the `Alt` key on a PC keyboard and the `Option` key on an Apple keyboard.

The prefix key is set to `C-o`

Some of the keyboard shortcuts that will be most useful to you are:

* `M-Up`, `M-Down` - switch between byobu sessions
* `M-Left`, `M-Right` - switch between windows in a session
* `shift-Left`, `shift-Right`, `shift-Up`, `shift-Down` - switch between panes in a window
  * Windows users using Conemu must first disable "Start selection with Shift+Arrow" in "Mark/Copy" under the "Keys & Macro" settings
* `C-o C-s` - synchronize panes
* `C-o z` - zoom into and out of a pane
* `C-o M-1` - evenly split panes horizontally
* `C-o M-2` - evenly split panes vertically
* `M-pageup`, `M-pagedown` - page up/down in scrollback

Note: `Shift-F2` does not create horizontal splits for Windows users. Use the `C-o |` key binding instead.
