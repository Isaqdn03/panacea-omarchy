-- >>> panacea-omarchy >>>
-- Panacea pill pages, opened through the pill's own IPC. `qs -c panacea` is the
-- same Quickshell instance that draws the pill, so `ipc call` reaches it without
-- Panacea's own Hyprland config -- which we deliberately do not install.
--
-- I = Inbox, U = Usage. Both are free with a single SUPER in Quattro;
-- SUPER + G is taken, which is why "GitHub" is not on G.
o.bind("SUPER + I", "GitHub inbox", "qs -c panacea ipc call pill github")
o.bind("SUPER + U", "Agent usage", "qs -c panacea ipc call pill agents")
-- <<< panacea-omarchy <<<
