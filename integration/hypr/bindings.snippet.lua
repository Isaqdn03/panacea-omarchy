-- >>> panacea-omarchy >>>
-- Panacea pill pages, opened through the pill's own IPC. `qs -c panacea` is the
-- same Quickshell instance that draws the pill, so `ipc call` reaches it without
-- Panacea's own Hyprland config -- which we deliberately do not install.
--
-- I = Inbox, U = Usage. Both are free with a single SUPER in Quattro;
-- SUPER + G is taken, which is why "GitHub" is not on G.
o.bind("SUPER + I", "GitHub inbox", "qs -c panacea ipc call pill github")
o.bind("SUPER + U", "Agent usage", "qs -c panacea ipc call pill agents")

-- Glass mode: Hyprland blur plus the terminal's transparent background, on or
-- off together. The script is the whole feature -- the pill's switch and this
-- key both just run it, and the pill notices the state change either way.
--
-- T for transparency. G would be the obvious letter and every G is taken:
-- SUPER + G groups windows, and SHIFT/ALT/CTRL + G are Signal, group-move and
-- Google Messages.
o.bind("SUPER + SHIFT + T", "Glass mode", "$HOME/.config/panacea/scripts/glass.sh")
-- <<< panacea-omarchy <<<
