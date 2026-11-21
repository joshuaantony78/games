# Scrolling World (Godot 4 port of joo2.py)

Open `project.godot` in **Godot 4.2+** and press F5.

Flow: intro image (press **Enter**) -> intro video (**Esc** skips) -> game.

Controls: **Left/Right** move, **Space** jump, **B** throw bomb.

Notes
- `video.mp4` was converted to `assets/video.ogv` (Godot only plays Ogg Theora).
- The restart-when-out-of-bombs check now waits for the last bomb to land,
  so the level can actually be completed.
