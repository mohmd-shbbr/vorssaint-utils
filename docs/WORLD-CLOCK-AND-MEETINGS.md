# World clock and upcoming meetings

Configure both features in **Settings → Menu bar**. Settings search also finds
that page for “World clock”, “Time zones”, “Calendars”, and “Upcoming meetings”.

## World clock

Enable **Show world time in the menu bar**, add timezones by city or timezone
identifier, give them labels, and choose which one appears in the menu bar.
The compact menu item stacks its label above the time. The 12/24-hour format is configurable.

Click the menu bar time to open the **World clock** page in Dynamic Island.
The page stays pinned while you plan; collapse it or press Escape when finished.
Two compact tiles show local time and the selected timezone side by side.
The scrolling ruler reuses the timer's native orange ticks, center pointer,
edge fade, drag/trackpad controls, keyboard navigation and haptics. It scrubs
±24 hours in 15-minute steps. Arrow buttons also move by 15 minutes.
Click either timezone tile to choose a date and time in that timezone;
the other tile updates to the same instant. This also lets you plan on any
other date. Every displayed city uses the same absolute instant, and offsets are recalculated for that date, including daylight
saving. **Now** returns all clocks to the current time. Clock changes do not
start, stop, or alter existing timers.

If Dynamic Island is disabled or its World clock page is hidden, the menu bar
clock opens a compact comparison popover instead. Timezone settings travel in
Vorssaint's existing local settings export/import.

## Calendar selection and upcoming meetings

Enable **Show upcoming meetings in the menu bar** and explicitly select your
calendars. **Clear all** followed by the desired calendars is a convenient way
to exclude holiday, birthday, and subscribed calendars. Selection also applies
to the Dynamic Island calendar and its event countdowns.

The initial **Use these calendars** action confirms the currently checked
choices. Until a selection is confirmed, the new menu item asks you to choose
calendars; existing Dynamic Island exclusions remain in effect. After you make
a selection, newly added calendars stay hidden until you select them. An empty
selection means no calendars, never “all calendars”.

The menu bar shows the next meeting or a meeting already in progress, along
with its countdown. You can hide the meeting title and adjust the look-ahead
window. Click to see the upcoming agenda or open an event date in Calendar.
All-day, canceled, declined, and already ended events are excluded from this
meeting list. Calendar access is requested through the existing macOS Calendar
permission flow. Event contents are read locally and never persisted by this
feature.

Calendar identifiers are part of the local backup. Accounts may assign different
identifiers on another Mac; choose the corresponding calendars again there if
needed.
