# Reminder overlay boundary

`ReminderOverlayWindowController` owns the long-lived AppKit window lifecycle, while
`ReminderOverlayView` reads provider-neutral reminder content from `ReminderOverlayStore` and
hosts `ReminderControlStripView`. `ReminderPresentationCoordinator` routes deduplicated local
scheduler results into this directly visible surface.

The reminder is presented as one compact horizontal control strip: a calendar-colour accent, a
scheduled-time region, event content, and quiet actions. `ReminderStripPresentation` computes the
displayed strings once per presentation, so the strip never runs a countdown or a timer.
`ReminderStripStyle` holds every spacing, typography, colour, and motion constant.

The strip is content-sized. The controller measures `NSHostingView.fittingSize`, clamps only the
width between a documented minimum and the smaller of the style maximum and the display's usable
width, then measures again at the constrained width so intrinsic height remains accurate. It places
the result at upper center inside `NSScreen.visibleFrame` through
`ScreenPlacement.reminderStripFrame`. Entry scales the strip from 94% to full size with a restrained
spring while the window fades in at that final frame. Automatic expiry reverses the scale and fades
the window out without horizontal travel. Reduce Motion uses an in-place fade without scaling.

Reminders are temporary by default and exit automatically after the configured duration; Settings
offers an explicit Timed/Persistent mode while retaining the stored Boolean representation for
compatibility. Dismiss, ten-minute snooze, and supported
source-opening actions persist through the scheduler before the overlay advances. Google Calendar
events do not expose a task-completion semantic, so completion remains limited to Google Tasks in
the persistent task panel. Calendar Open uses a provider-supplied Google Calendar web link; the
overlay never depends on Apple Calendar or Google transport DTOs.
