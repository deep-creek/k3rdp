// Tiny X11 helper, deliberately in its own translation unit: <X11/Xlib.h> defines
// macros (Bool, None, Status, …) that collide with Qt identifiers, so we keep it
// away from any Qt include.
//
// Sets WM_CLASS on an already-created (but not-yet-mapped) X window. Used to give
// the sample's test dialog a WM_CLASS distinct from the app's "qtapp", so the
// kiosk winoptions (which strip decorations for "qtapp") don't match it and it
// keeps IceWM's default, draggable title bar.

#include <X11/Xlib.h>
#include <X11/Xutil.h>

void setWmClass(unsigned long window, const char *nameAndClass)
{
    Display *dpy = XOpenDisplay(nullptr);
    if (!dpy)
        return;
    XClassHint hint;
    hint.res_name = const_cast<char *>(nameAndClass);
    hint.res_class = const_cast<char *>(nameAndClass);
    XSetClassHint(dpy, static_cast<Window>(window), &hint);
    XSync(dpy, False);   // ensure the server records it before the caller maps the window
    XCloseDisplay(dpy);
}
