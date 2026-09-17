pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import ".."
import "../../colors"
import "../../services"
import "../../config"

/**
 * astralis — month calendar surface (Ricelin Calendar.qml layout, now with
 * its events). To the left, Ricelin's weather glance: the condition glyph
 * beside the current temperature and its label, the city (tap to type — sets
 * Flags.weatherCity and re-geocodes; blank it for auto IP detection) with
 * humidity, then a four-day outlook strip. The network flakes on this box,
 * so until Weather.ready the panel shows dim "—" placeholders — never an
 * error. Then a hairline seam and the month grid: "暦 <MONTH YEAR>" header
 * with ‹ › nav squares, a hairline divider, narrow Monday-first weekday
 * initials (weekends dim), and the day grid: hover squares, ghost numbers
 * for the neighbouring months, today in a Colors.primary-ringed square. A
 * day holding a stored event marks its number in the tertiary ember with a
 * small dot beneath. Tap the month label to jump back to today.
 *
 * To the right, the Ricelin event editor: picking a day lists its events
 * (delete on hover) above an add form — title + add button, an All day/Timed
 * segment (Timed reveals HH:MM start/end fields), a Once/Monthly/Yearly
 * repeat segment (a birthday-looking title suggests Yearly by itself), and a
 * span control that arms the grid so the next day click closes a multi-day
 * range. Ricelin slides this column open by morphing the pill wider; astralis
 * sizes surfaces FIXED (Pill.qml descriptor), so the column is always present
 * at Ricelin's full-open width and the open reset selects today instead of
 * nothing — deselect (re-click the day, or click under the grid) and the
 * column rests as a faint hint. The list flexes to the leftover height and
 * scrolls instead of growing the surface.
 *
 * The soul bead rings the picked day, or today when this month is in view
 * with nothing picked; browsing another month unfocused parks it as a soul
 * ember on the 暦 header glyph (Ricelin's calendar lantern).
 */
PillSurface {
    id: root

    mTop: 16
    mLeft: 18
    mRight: 18
    mBottom: 16

    readonly property var loc: Qt.locale()

    property var today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    /**
     * Absolute month ordinal, so a step across the year boundary still reads as
     * one move in one direction. The day grid is a single live Repeater — it
     * cannot cross-fade against itself — so a month swap replays as an ARRIVAL
     * instead (gridFlip): the rebound cells slide in from the side the month
     * came from, rather than 42 numbers silently blinking over. lastMonthIndex
     * starts at -1 so the first binding pass has a sentinel to compare against
     * instead of reading as a step backwards.
     */
    readonly property int monthIndex: viewYear * 12 + viewMonth
    property int lastMonthIndex: -1
    onMonthIndexChanged: {
        var dir = (lastMonthIndex < 0 || monthIndex > lastMonthIndex) ? 1 : -1;
        lastMonthIndex = monthIndex;
        // Only while the surface is up: the month settled during construction
        // (and any midnight roll on a closed pill) has no arrival to play, and
        // gridFlip's id is not resolvable that early either.
        if (open && !Motion.reduceMotion) {
            gridFlip.dir = dir;
            gridFlip.restart();
        }
    }

    readonly property int offset: firstWeekdayOffset(viewYear, viewMonth)
    readonly property int monthLen: daysInMonth(viewYear, viewMonth)

    readonly property real cellH: 24 * s
    readonly property real rowGap: 2 * s

    readonly property real gridW: 282 * s
    readonly property real weatherW: 152 * s
    readonly property real editorW: 196 * s
    readonly property real gutter: 16 * s

    // Dim placeholder tone for the weather glance before the first clean fetch.
    readonly property color wxFaint: Qt.alpha(Colors.on_surface_variant, 0.65)
    // Hairline (Ricelin Theme.hair).
    readonly property color hair: Qt.alpha(Colors.on_surface, 0.06)

    /**
     * Selection: selectedDate is the picked day (and a span's start), selEndDate
     * the span's last day or "" for a single day. pickingEnd arms the grid so the
     * next day click closes the span; hoverDay previews that span live while the
     * pointer moves. Keys are zero-padded "YYYY-MM-DD" so a string compare spans
     * them, even across months.
     */
    property string selectedDate: ""
    property string selEndDate: ""
    property bool pickingEnd: false
    property int hoverDay: 0

    readonly property bool editorShown: selectedDate.length > 0

    /** Span end the grid paints: the live hover while arming, else the set end. */
    readonly property string rangeEndKey: pickingEnd && hoverDay > 0 ? dateKey(hoverDay) : selEndDate
    readonly property string rangeLo: {
        if (selectedDate.length === 0) return "";
        var b = rangeEndKey;
        if (b.length === 0) return selectedDate;
        return selectedDate < b ? selectedDate : b;
    }
    readonly property string rangeHi: {
        if (selectedDate.length === 0) return "";
        var b = rangeEndKey;
        if (b.length === 0) return selectedDate;
        return selectedDate < b ? b : selectedDate;
    }
    function inRange(key) {
        return key.length > 0 && rangeLo.length > 0 && key >= rangeLo && key <= rangeHi;
    }

    /** "ddd d MMM" for a single day, "d MMM" without the weekday. */
    function fmtDay(key, dow) {
        var p = key.split("-");
        var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
        return loc.toString(d, dow ? "ddd d MMM" : "d MMM");
    }

    /** "22–25 Jun" within a month, "29 Jun – 2 Jul" across one. */
    function fmtSpan(loKey, hiKey) {
        var lp = loKey.split("-");
        var hp = hiKey.split("-");
        if (lp[0] === hp[0] && lp[1] === hp[1]) {
            var d = new Date(Number(lp[0]), Number(lp[1]) - 1, Number(lp[2]));
            return Number(lp[2]) + "–" + Number(hp[2]) + " " + loc.toString(d, "MMM");
        }
        return fmtDay(loKey, false) + " – " + fmtDay(hiKey, false);
    }

    function firstWeekdayOffset(year, month) {
        var d = new Date(year, month, 1).getDay();
        return (d + 6) % 7;    // Monday-first
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    function isToday(day) {
        return day === today.getDate()
            && viewMonth === today.getMonth()
            && viewYear === today.getFullYear();
    }

    /** "YYYY-MM-DD" for a day number in the viewed month, zero-padded for keys. */
    function dateKey(day) {
        var m = viewMonth + 1;
        var mm = m < 10 ? "0" + m : "" + m;
        var dd = day < 10 ? "0" + day : "" + day;
        return viewYear + "-" + mm + "-" + dd;
    }

    function shiftMonth(delta) {
        var m = viewMonth + delta;
        var y = viewYear;
        while (m < 0) { m += 12; y -= 1; }
        while (m > 11) { m -= 12; y += 1; }
        viewMonth = m;
        viewYear = y;
        hoverDay = 0;
        if (!pickingEnd) {
            selectedDate = "";
            selEndDate = "";
        }
    }

    /**
     * Ricelin resets to nothing picked; here the editor column is a fixed
     * fixture, so the reset picks today — the column opens on today's events
     * instead of an empty hint.
     */
    function resetToday() {
        today = new Date();
        viewYear = today.getFullYear();
        viewMonth = today.getMonth();
        selEndDate = "";
        pickingEnd = false;
        hoverDay = 0;
        selectedDate = dateKey(today.getDate());
    }

    /**
     * Click handling: while arming a span the next click sets its end (clicking
     * the start again drops the span); a click below the start swaps the two so
     * the earlier day stays the start. Otherwise it toggles a single day and
     * re-clicking the open day rests the editor.
     */
    function selectDay(day) {
        var key = dateKey(day);
        if (pickingEnd) {
            pickingEnd = false;
            hoverDay = 0;
            if (key === selectedDate)
                selEndDate = "";
            else if (key < selectedDate) {
                selEndDate = selectedDate;
                selectedDate = key;
            } else {
                selEndDate = key;
            }
            return;
        }
        if (selectedDate === key && selEndDate.length === 0) {
            selectedDate = "";
            return;
        }
        selectedDate = key;
        selEndDate = "";
    }

    // Reset to the real today on every open so a stale month never greets you,
    // and arm the midnight roll so a long-open surface never keeps a stale day.
    onOpenChanged: {
        if (open) {
            resetToday();
            midnightTimer.arm();
        } else {
            midnightTimer.stop();
        }
    }

    // Fire at the next LOCAL midnight and re-arm for the following day, so the
    // "today" ring and labels refresh if the surface is left open past midnight.
    // The Date ctor with day+1 rolls month/year and lands on real local
    // midnight (DST-safe), so the interval is a plain wall-clock delta.
    Timer {
        id: midnightTimer
        repeat: false
        onTriggered: {
            root.resetToday();
            midnightTimer.arm();
        }
        function arm() {
            var now = new Date();
            var next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 2);
            interval = Math.max(1000, next.getTime() - now.getTime());
            restart();
        }
    }

    readonly property bool todayVisible: viewMonth === today.getMonth()
        && viewYear === today.getFullYear()

    /**
     * Ame is the focus cursor: it rings the picked day, or today when this
     * month is in view with nothing picked. Browsing another month with
     * nothing picked leaves no focus, so the bead parks as a soul ember on
     * the 暦 header glyph rather than floating over a random date cell.
     */
    readonly property bool selectedInView: selectedDate.length > 0
        && Number(selectedDate.split("-")[1]) === viewMonth + 1
        && Number(selectedDate.split("-")[0]) === viewYear
    readonly property int focusDay: selectedInView
        ? Number(selectedDate.split("-")[2])
        : (todayVisible ? today.getDate() : 0)
    readonly property bool focused: focusDay > 0
    readonly property int focusIndex: offset + focusDay - 1
    readonly property real cellW: grid.width / 7
    readonly property real focusX: gridPane.x + grid.x + (focusIndex % 7 + 0.5) * cellW
    readonly property real focusY: gridPane.y + grid.y + (Math.floor(focusIndex / 7) + 0.5) * (cellH + rowGap) - rowGap / 2

    /**
     * The parked ember hangs a bead's diameter BELOW the 暦 glyph box, wick
     * rising back up into the strokes — the header glyph is the lantern
     * carrying the flame, the same idiom Sysmon and Recorder use and the same
     * one the pill's own hover ember uses under a status icon. It sat 3*s
     * ABOVE the glyph before, which put the wick's ~11.3*s of ink past the
     * pill's top edge (the Ame canvas fills the pill and cuts anything
     * outside), leaving a bare dot stuck to the border.
     */
    readonly property point soulPoint: {
        void width;
        void height;
        // When glyphs are hidden calGlyph drops out of the header Row (width→0),
        // so the ember hangs under the month label's leading letters instead of
        // the collapsed glyph. Under, not beside: this pane's left gutter is
        // where the weather divider hairline runs, so the sideways fallback
        // Sysmon/Recorder use (they have the surface's own margin there) would
        // drop the bead straight onto the seam.
        if (Flags.showGlyphs)
            return calGlyph.mapToItem(root, calGlyph.width / 2, calGlyph.height + 6 * s);
        return monthLabel.mapToItem(root, 6 * s, monthLabel.height + 6 * s);
    }

    ameForm: focused ? "ring" : "soul"
    amePoint: focused ? Qt.point(focusX, focusY) : soulPoint

    /**
     * Mini-segmented choice control (Ricelin SettingsSeg, inlined — astralis
     * has no shared seg widget yet and this surface is its only taker).
     * `options` is a list of `{ label, value }`; the pill whose value equals
     * `value` lights with an ember tint. Picking a pill emits `picked(value)`.
     */
    component Seg: Rectangle {
        id: seg

        property var options: []
        property var value
        signal picked(var value)

        readonly property real pad: 1

        width: segPills.implicitWidth + 2 * pad
        height: segPills.implicitHeight + 2 * pad
        radius: 9 * root.s
        color: "transparent"

        Row {
            id: segPills
            anchors.centerIn: parent
            spacing: 2 * root.s

            Repeater {
                model: seg.options

                Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool current: seg.value === modelData.value

                    width: optLabel.implicitWidth + 18 * root.s
                    height: optLabel.implicitHeight + 12 * root.s
                    radius: 8 * root.s
                    color: opt.current ? Qt.alpha(Colors.tertiary, 0.16)
                        : (optArea.containsMouse ? Colors.surface_container_highest : "transparent")
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    // One choice among the segment's options (SettingsSeg idiom).
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: String(opt.modelData.label)
                    Accessible.checkable: true
                    Accessible.checked: opt.current
                    Accessible.focusable: true
                    Accessible.onPressAction: seg.picked(opt.modelData.value)

                    scale: optArea.pressed ? 0.92 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    Text {
                        id: optLabel
                        anchors.centerIn: parent
                        text: opt.modelData.label
                        color: opt.current ? Colors.on_surface : Colors.on_surface_variant
                        font.family: Appearance.font.family
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 0.3 * root.s
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    MouseArea {
                        id: optArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(opt.modelData.value)
                    }
                }
            }
        }
    }

    // ── weather glance (Ricelin Calendar.qml weather panel) ─────────────────
    Item {
        id: weather
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.weatherW

        Column {
            id: wxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 6 * root.s
            spacing: 9 * root.s

            Row {
                spacing: 9 * root.s

                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32 * root.s
                    height: 32 * root.s
                    name: Weather.glyphFor(Weather.codeNow, Weather.isDay)
                    color: Weather.ready ? Colors.primary : root.wxFaint
                    stroke: 1.9
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        text: Weather.ready ? Weather.tempNow + "°" : "—"
                        color: Weather.ready ? Colors.on_surface : root.wxFaint
                        font.family: Appearance.font.family
                        font.pixelSize: 26 * root.s
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        text: Weather.ready ? Weather.labelFor(Weather.codeNow) : "—"
                        color: Weather.ready ? Colors.on_surface_variant : root.wxFaint
                        font.family: Appearance.font.family
                        font.pixelSize: 10 * root.s
                        font.weight: Font.Medium
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 8 * root.s

                /**
                 * IP geolocation only ever resolves to the ISP city, so the town
                 * is editable in place: tap to type, which sets Flags.weatherCity
                 * and re-geocodes through Open-Meteo for the exact spot. Blank it
                 * to fall back to auto IP detection.
                 */
                Item {
                    id: cityBox
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - humidityRow.width - 8 * root.s
                    height: 14 * root.s

                    property bool editing: false

                    Text {
                        id: cityText
                        visible: !cityBox.editing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.city.length > 0 ? Weather.city : "set town"
                        color: cityArea.containsMouse ? Colors.on_surface_variant : root.wxFaint
                        font.family: Appearance.font.family
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8 * root.s
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                        Accessible.role: Accessible.Button
                        Accessible.name: "Weather city"
                        Accessible.description: "Tap to set a town; leave blank for automatic location"
                        Accessible.focusable: true
                        Accessible.onPressAction: {
                            cityField.text = Flags.weatherCity;
                            cityBox.editing = true;
                            cityField.forceActiveFocus();
                            cityField.selectAll();
                        }

                        // Pressed from the left edge: the label is anchored
                        // across the whole box but its ink sits hard left, so a
                        // centre dip would slide the town sideways.
                        transformOrigin: Item.Left
                        scale: cityArea.pressed ? 0.96 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }
                    }
                    MouseArea {
                        id: cityArea
                        visible: !cityBox.editing
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            cityField.text = Flags.weatherCity;
                            cityBox.editing = true;
                            cityField.forceActiveFocus();
                            cityField.selectAll();
                        }
                    }
                    TextField {
                        id: cityField
                        visible: cityBox.editing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        background: null
                        padding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8 * root.s
                        placeholderText: "town"
                        Accessible.name: "Weather city"
                        placeholderTextColor: root.wxFaint
                        selectByMouse: true
                        selectionColor: Colors.primary
                        onAccepted: {
                            Flags.weatherCity = text.trim();
                            cityBox.editing = false;
                        }
                        Keys.onEscapePressed: cityBox.editing = false
                        onActiveFocusChanged: if (!activeFocus) cityBox.editing = false
                    }
                }
                Row {
                    id: humidityRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        // 13·s — see pill/Toast.qml's dismiss icon note (a
                        // stroked glyph below ~13·s can't rasterize thin
                        // enough to stay crisp).
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "droplet"
                        color: root.wxFaint
                        stroke: 1.6
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.ready ? Weather.humidity + "%" : "—"
                        color: root.wxFaint
                        font.family: Appearance.font.family
                        font.pixelSize: 9.5 * root.s
                        font.weight: Font.Medium
                        font.features: ({ "tnum": 1 })
                    }
                }
            }

            Rectangle {
                width: wxCol.width
                height: 1
                color: Qt.alpha(Colors.on_surface, 0.04)
            }

            // Four-day outlook: Weather.daily stays [] until a fetch lands,
            // so the strip is simply blank while the network is down.
            Row {
                width: wxCol.width

                Repeater {
                    model: Weather.daily.slice(0, 4)

                    Column {
                        id: dayCol
                        required property var modelData
                        width: wxCol.width / 4
                        spacing: 5 * root.s

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCol.modelData.day
                            color: root.wxFaint
                            font.family: Appearance.font.family
                            font.pixelSize: 9 * root.s
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.5 * root.s
                        }
                        GlyphIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 15 * root.s
                            height: 15 * root.s
                            name: Weather.glyphFor(dayCol.modelData.code, true)
                            color: Colors.on_surface_variant
                            stroke: 1.7
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayCol.modelData.temp + "°"
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 11 * root.s
                            font.weight: Font.Medium
                            font.features: ({ "tnum": 1 })
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2 * root.s

                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                // 13·s — see pill/Toast.qml's dismiss icon
                                // note; 9·s was well below the floor where a
                                // stroked glyph stays legible.
                                width: 13 * root.s
                                height: 13 * root.s
                                name: "droplet"
                                color: root.wxFaint
                                stroke: 1.6
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: dayCol.modelData.rh + "%"
                                color: root.wxFaint
                                font.family: Appearance.font.family
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.Medium
                                font.features: ({ "tnum": 1 })
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: weatherSeam
        anchors.left: weather.right
        anchors.leftMargin: root.gutter / 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: root.hair
    }

    // ── month grid pane ─────────────────────────────────────────────────────
    Item {
        id: gridPane
        anchors.left: weather.right
        anchors.leftMargin: root.gutter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.gridW

        // ── header: 暦 MONTH YEAR + ‹ › ─────────────────────────────────────
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    id: calGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "暦"
                    color: Colors.on_surface
                    font.family: Appearance.font.jp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    id: monthLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.loc.standaloneMonthName(root.viewMonth, Locale.LongFormat)
                        + " " + root.viewYear
                    // The label is a button with no chrome of its own, so
                    // hover has to say so — it lifts to on_surface the same way
                    // the nav squares' chevrons do.
                    color: monthArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                    font.family: Appearance.font.family
                    font.pixelSize: 11 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.0 * root.s
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Accessible.role: Accessible.Button
                    Accessible.name: "Jump to today"
                    Accessible.description: monthLabel.text
                    Accessible.focusable: true
                    Accessible.onPressAction: root.resetToday()

                    scale: monthArea.pressed ? 0.96 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    // Tap the label to jump back to today.
                    MouseArea {
                        id: monthArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetToday()
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * root.s

                Repeater {
                    model: [-1, 1]

                    Rectangle {
                        id: nav
                        required property int modelData
                        width: 22 * root.s
                        height: 22 * root.s
                        radius: Motion.rSmall * root.s
                        color: navArea.containsMouse ? Colors.surface_container_highest : "transparent"
                        // The outline is always drawn and only its colour
                        // travels: toggling border.width instead snaps the ring
                        // on with nothing to animate between.
                        border.width: 1
                        border.color: navArea.containsMouse
                            ? Qt.alpha(Colors.outline_variant, 0.9) : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        Accessible.role: Accessible.Button
                        Accessible.name: nav.modelData < 0 ? "Previous month" : "Next month"
                        Accessible.focusable: true
                        Accessible.onPressAction: root.shiftMonth(nav.modelData)

                        scale: navArea.pressed ? 0.92 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 16 * root.s
                            height: 16 * root.s
                            name: nav.modelData < 0 ? "chevron-left" : "chevron-right"
                            color: navArea.containsMouse ? Colors.on_surface : Colors.on_surface_variant
                            stroke: 1.8
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shiftMonth(nav.modelData)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: divider
            anchors.top: header.bottom
            anchors.topMargin: 9 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: root.hair
        }

        // ── weekday initials (Monday-first, weekends dim) ───────────────────
        Row {
            id: weekdays
            anchors.top: divider.bottom
            anchors.topMargin: 8 * root.s
            anchors.left: parent.left
            anchors.right: parent.right

            Repeater {
                model: 7

                Item {
                    id: wd
                    required property int index
                    readonly property bool weekend: index >= 5
                    width: weekdays.width / 7
                    height: 16 * root.s

                    Text {
                        anchors.centerIn: parent
                        text: root.loc.standaloneDayName((wd.index + 1) % 7, Locale.NarrowFormat)
                        // Two-tone weekend cue: weekdays read at full on_surface,
                        // weekends drop to on_surface_variant — a legible role gap
                        // rather than a dim-on-dim alpha that fails contrast.
                        color: wd.weekend ? Colors.on_surface_variant : Colors.on_surface
                        font.family: Appearance.font.family
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Medium
                        font.letterSpacing: 0.5 * root.s
                    }
                }
            }
        }

        // ── day grid ────────────────────────────────────────────────────────
        Grid {
            id: grid
            y: weekdays.y + weekdays.height + 4 * root.s
            anchors.left: parent.left
            anchors.right: parent.right
            columns: 7
            rowSpacing: root.rowGap
            columnSpacing: 0

            // Driven by gridFlip on a month change. A Translate rather than
            // `x`: the Grid is anchored to both pane edges, so its x is not
            // ours to set — and the focus bead's coordinates read grid.x, so
            // the bead holds still while the cells travel under it.
            transform: Translate { id: gridSlide }

            Repeater {
                model: 42

                Item {
                    id: cell
                    required property int index
                    readonly property int weekday: index % 7
                    readonly property bool weekend: weekday >= 5
                    width: grid.width / 7
                    height: root.cellH

                    readonly property int dayNum: index - root.offset + 1
                    readonly property bool inMonth: dayNum >= 1 && dayNum <= root.monthLen
                    readonly property bool current: inMonth && root.isToday(dayNum)
                    readonly property string dayKey: inMonth ? root.dateKey(dayNum) : ""
                    readonly property bool hasEvent: inMonth && Events.hasEvents(cell.dayKey)
                    readonly property bool sel: inMonth && root.inRange(cell.dayKey)
                    readonly property bool selEdge: cell.sel
                        && (cell.dayKey === root.rangeLo || cell.dayKey === root.rangeHi)
                    readonly property int ghostNum: dayNum < 1
                        ? root.daysInMonth(root.viewYear, root.viewMonth - 1) + dayNum
                        : dayNum - root.monthLen

                    // Ghost cells (the neighbouring month's fill) are dropped
                    // from the accessibility tree entirely rather than exposed
                    // disabled — they carry no date this surface can act on.
                    Accessible.ignored: !cell.inMonth
                    Accessible.role: Accessible.Button
                    Accessible.name: cell.inMonth ? "" + cell.dayNum + (cell.current ? ", today" : "") : ""
                    Accessible.description: cell.inMonth && cell.hasEvent ? "Has events" : ""
                    Accessible.selected: cell.sel
                    Accessible.focusable: cell.inMonth
                    Accessible.onPressAction: if (cell.inMonth) root.selectDay(cell.dayNum)

                    // Shallower than a tile's dip: a square this small reads as
                    // a twitch at 0.96. Ghost cells never press — their
                    // MouseArea is disabled, so `pressed` stays false there.
                    scale: cellArea.pressed ? 0.94 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.glide
                            easing.type: Motion.easeBezier
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 22 * root.s
                        height: 22 * root.s
                        radius: Motion.rSmall * root.s
                        color: cellArea.containsMouse && cell.inMonth && !cell.current
                            ? Qt.alpha(Colors.on_surface, 0.04) : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 24 * root.s
                        height: 24 * root.s
                        radius: Motion.rSmall * root.s
                        // Faded, not flipped. Kept on the short hover duration
                        // rather than the slower state cross-fade because while
                        // a span is being armed this repaints under the moving
                        // pointer, and 300ms would smear across the row.
                        opacity: (cell.current || cell.sel) ? 1 : 0
                        visible: opacity > 0.01
                        color: cell.sel && !cell.current
                            ? Qt.alpha(Colors.tertiary, 0.12) : Qt.alpha(Colors.primary, 0.14)
                        border.width: 1
                        border.color: cell.selEdge ? Qt.alpha(Colors.tertiary, 0.55)
                            : (cell.sel ? Qt.alpha(Colors.tertiary, 0.22) : Colors.primary)
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cell.inMonth ? cell.dayNum : cell.ghostNum
                        color: cell.inMonth
                            ? (cell.current ? Colors.primary
                                : (cell.hasEvent ? Colors.tertiary
                                    : (cell.weekend ? Colors.on_surface_variant : Colors.on_surface)))
                            : Qt.alpha(Colors.on_surface_variant, 0.6)
                        opacity: cell.inMonth && !cell.current && !cell.weekend && !cell.hasEvent ? 0.85 : 1.0
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        font.weight: cell.current || cell.hasEvent ? Font.DemiBold : Font.Normal
                        font.features: ({ "tnum": 1 })
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }

                    // Ember dot for a day holding a stored event.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.verticalCenter
                        anchors.topMargin: 9 * root.s
                        opacity: cell.hasEvent && !cell.current ? 1 : 0
                        visible: opacity > 0.01
                        width: 3 * root.s
                        height: 3 * root.s
                        radius: width / 2
                        color: Colors.tertiary
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }

                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: cell.inMonth
                        cursorShape: cell.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (cell.inMonth) root.selectDay(cell.dayNum)
                        onContainsMouseChanged: {
                            if (root.pickingEnd && cell.inMonth && containsMouse)
                                root.hoverDay = cell.dayNum;
                            else if (!containsMouse && root.hoverDay === cell.dayNum)
                                root.hoverDay = 0;    // clear on exit so a stale preview never lingers
                        }
                    }
                }
            }
        }

        /**
         * The month arrival. The cells are already rewritten by the time this
         * runs, so there is nothing left to fade OUT — it starts the new month
         * offset and transparent and walks it home, which reads as the grid
         * turning a page in the direction of travel.
         */
        SequentialAnimation {
            id: gridFlip
            property int dir: 1
            PropertyAction { target: gridSlide; property: "x"; value: gridFlip.dir * 16 * root.s }
            PropertyAction { target: grid; property: "opacity"; value: 0 }
            ParallelAnimation {
                NumberAnimation {
                    target: gridSlide
                    property: "x"
                    to: 0
                    duration: Motion.morph
                    easing.type: Motion.easeBezier
                    easing.bezierCurve: Motion.expressiveDefaultSpatial
                }
                NumberAnimation {
                    target: grid
                    property: "opacity"
                    to: 1
                    duration: Motion.standard
                    easing.type: Motion.easeStandard
                }
            }
        }

        // Click the leftover strip under the grid to drop the selection.
        MouseArea {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: grid.bottom
            anchors.bottom: parent.bottom
            enabled: root.editorShown && !root.pickingEnd
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.selectedDate = "";
                root.selEndDate = "";
                root.pickingEnd = false;
            }

            Accessible.role: Accessible.Button
            Accessible.name: "Clear date selection"
            Accessible.focusable: root.editorShown && !root.pickingEnd
            Accessible.onPressAction: {
                root.selectedDate = "";
                root.selEndDate = "";
                root.pickingEnd = false;
            }
        }

        Text {
            anchors.horizontalCenter: grid.horizontalCenter
            anchors.top: grid.bottom
            anchors.topMargin: 6 * root.s
            opacity: root.pickingEnd ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            text: "click the end day"
            color: Colors.tertiary
            font.family: Appearance.font.family
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.letterSpacing: 0.4 * root.s
        }
    }

    Rectangle {
        id: editorSeam
        anchors.left: gridPane.right
        anchors.leftMargin: root.gutter / 2
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: root.hair
    }

    // ── selected-day event editor (Ricelin Calendar.qml editor column) ──────
    Item {
        id: editor
        anchors.left: gridPane.right
        anchors.leftMargin: root.gutter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.editorW

        readonly property bool hasSel: root.selectedDate.length > 0

        /** Events covering the picked day (a span's start), empty until a day is picked. */
        readonly property var dayEvents: hasSel ? Events.eventsFor(root.selectedDate) : []

        /** Single day reads "Mon 9 Jun"; a span reads its range. */
        readonly property string heading: {
            if (!hasSel)
                return "";
            if (root.selEndDate.length === 0)
                return root.fmtDay(root.selectedDate, true);
            return root.fmtSpan(root.rangeLo, root.rangeHi);
        }

        readonly property string spanLabel: !hasSel ? ""
            : (root.selEndDate.length === 0
                ? root.fmtDay(root.selectedDate, false)
                : root.fmtSpan(root.rangeLo, root.rangeHi))

        /** "allday" (default) hides the time fields; "timed" reveals start/end. */
        property string mode: "allday"
        property string startVal: ""
        property string endVal: ""
        property string titleVal: ""

        /**
         * recur is "" / "month" / "year". It suggests yearly by itself once the
         * title reads like a birthday and then stays as the user left it after
         * they work the Repeat toggle by hand (recurManual).
         */
        property string recur: ""
        property bool recurManual: false

        /** Suggest yearly for a birthday title, unless the user already chose. */
        function autoRecur() {
            if (!recurManual)
                recur = Events.isBirthday(titleVal) ? "year" : "";
        }

        function clearForm() {
            startVal = "";
            endVal = "";
            titleVal = "";
            recur = "";
            recurManual = false;
            startField.text = "";
            endField.text = "";
            titleField.text = "";
        }

        /** A time is kept only when it reads as HH:MM, otherwise it drops to an all-day blank. */
        function cleanTime(t) {
            var v = t.trim();
            var m = /^(\d{1,2}):(\d{2})$/.exec(v);
            if (!m)
                return "";
            // Reject out-of-range clock values like "45:99".
            if (Number(m[1]) > 23 || Number(m[2]) > 59)
                return "";
            return v;
        }

        /** Add the form's event when a title is set, then reset the inputs. */
        function commit() {
            if (titleVal.trim().length === 0)
                return;
            var t = editor.mode === "timed" ? editor.cleanTime(startVal) : "";
            var e = editor.mode === "timed" ? editor.cleanTime(endVal) : "";
            Events.add(root.selectedDate, editor.recur !== "" ? "" : root.selEndDate,
                       t, e, titleVal.trim(), editor.recur);
            clearForm();
            // Reset per-event edit state so a span/mode never bleeds into the
            // next event added for this day.
            editor.mode = "allday";
            root.selEndDate = "";
            root.pickingEnd = false;
            root.hoverDay = 0;
            titleField.forceActiveFocus();
        }

        onHasSelChanged: if (!hasSel) { clearForm(); mode = "allday"; }

        // Fixed footprint (Ricelin morphs this column open): with no day
        // picked the column rests as a faint hint instead of collapsing.
        Text {
            anchors.centerIn: parent
            visible: opacity > 0.01
            opacity: editor.hasSel ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            text: "pick a day"
            color: root.wxFaint
            font.family: Appearance.font.family
            font.pixelSize: 11 * root.s
            font.weight: Font.Medium
            font.italic: true
        }

        Item {
            id: edBody
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: editor.hasSel ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            Column {
                id: edTop
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8 * root.s

                Text {
                    width: parent.width
                    text: editor.heading
                    color: Colors.on_surface
                    font.family: Appearance.font.family
                    font.pixelSize: 12 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8 * root.s
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.hair
                }
            }

            /**
             * The day's events, flexed to whatever height the fixed column has
             * left over the form, so a stacked day scrolls instead of growing
             * the surface (Ricelin caps this at 230 and grows the pill).
             */
            Flickable {
                id: edFlick
                anchors.top: edTop.bottom
                anchors.topMargin: 8 * root.s
                anchors.bottom: edForm.top
                anchors.bottomMargin: 8 * root.s
                anchors.left: parent.left
                anchors.right: parent.right
                contentHeight: edList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentHeightChanged: returnToBounds()

                Column {
                    id: edList
                    width: edFlick.width
                    spacing: 4 * root.s

                    Text {
                        visible: editor.dayEvents.length === 0
                        text: "Nothing yet"
                        color: root.wxFaint
                        font.family: Appearance.font.family
                        font.pixelSize: 11 * root.s
                        font.weight: Font.Medium
                        font.italic: true
                    }

                    Repeater {
                        model: editor.dayEvents

                        Rectangle {
                            id: evRow
                            required property var modelData
                            required property int index
                            width: edList.width
                            height: evBody.implicitHeight + 12 * root.s
                            radius: Motion.rSmall * root.s
                            color: evArea.hovered ? Colors.surface_container_highest : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            /**
                             * Entrance cascade. The model only swaps on a
                             * discrete act — picking a day, adding or deleting
                             * an event — never per keystroke, so the wave reads
                             * as the day's list arriving rather than replaying
                             * under the user's hands.
                             */
                            property bool entered: false
                            opacity: evRow.entered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                            transform: Translate {
                                y: evRow.entered ? 0 : 10 * root.s
                                Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                            }
                            Timer {
                                interval: Motion.rowStagger * Math.min(evRow.index, 10)
                                running: true
                                onTriggered: evRow.entered = true
                            }

                            /** "all day" or "09:00–10:00", a date span when multi-day, "every year" when recurring. */
                            readonly property string meta: {
                                var datePart = "";
                                if (evRow.modelData.endDate && evRow.modelData.endDate.length > 0)
                                    datePart = root.fmtSpan(evRow.modelData.date, evRow.modelData.endDate);
                                var t = evRow.modelData.time || "";
                                var e = evRow.modelData.endTime || "";
                                // All-day only when BOTH ends are blank; a lone end
                                // (blank start) still shows its time rather than
                                // masquerading as all-day and hiding endTime.
                                var timePart;
                                if (t.length === 0 && e.length === 0)
                                    timePart = "all day";
                                else if (t.length > 0 && e.length > 0)
                                    timePart = t + "–" + e;
                                else if (t.length > 0)
                                    timePart = t;
                                else
                                    timePart = "until " + e;
                                var base = datePart.length > 0 ? datePart + " · " + timePart : timePart;
                                var r = evRow.modelData.recur;
                                if (r === "year") return "every year · " + base;
                                if (r === "month") return "every month · " + base;
                                return base;
                            }

                            HoverHandler { id: evArea }

                            Column {
                                id: evBody
                                anchors.left: parent.left
                                anchors.leftMargin: 8 * root.s
                                anchors.right: evDel.left
                                anchors.rightMargin: 6 * root.s
                                anchors.top: parent.top
                                anchors.topMargin: 6 * root.s
                                spacing: 2 * root.s

                                Text {
                                    text: evRow.modelData.text
                                    width: parent.width
                                    color: Colors.on_surface
                                    font.family: Appearance.font.family
                                    font.pixelSize: 11 * root.s
                                    font.weight: Font.Medium
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: evRow.meta
                                    width: parent.width
                                    color: Colors.tertiary
                                    font.family: Appearance.font.family
                                    font.pixelSize: 9 * root.s
                                    font.weight: Font.DemiBold
                                    font.features: ({ "tnum": 1 })
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                }
                            }

                            Item {
                                id: evDel
                                anchors.right: parent.right
                                anchors.rightMargin: 7 * root.s
                                anchors.top: parent.top
                                anchors.topMargin: 7 * root.s
                                width: 16 * root.s
                                height: 16 * root.s
                                opacity: evArea.hovered ? 1 : 0.32
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                Accessible.role: Accessible.Button
                                Accessible.name: "Remove event"
                                Accessible.description: evRow.modelData.text
                                Accessible.focusable: true
                                Accessible.onPressAction: Events.remove(evRow.modelData.id)

                                scale: delArea.pressed ? 0.92 : 1
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Motion.glide
                                        easing.type: Motion.easeBezier
                                        easing.bezierCurve: Motion.expressiveFastSpatial
                                    }
                                }

                                GlyphIcon {
                                    anchors.fill: parent
                                    name: "close"
                                    color: delArea.containsMouse ? Colors.tertiary : Colors.on_surface_variant
                                    stroke: 1.6
                                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                                }

                                MouseArea {
                                    id: delArea
                                    anchors.fill: parent
                                    anchors.margins: -5 * root.s
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Events.remove(evRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ── add form, pinned to the column floor ────────────────────────
            Column {
                id: edForm
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 8 * root.s

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.hair
                }

                Row {
                    width: parent.width
                    spacing: 8 * root.s

                    Item {
                        width: parent.width - addBtn.width - 8 * root.s
                        height: 28 * root.s

                        TextField {
                            id: titleField
                            anchors.fill: parent
                            background: null
                            padding: 0
                            leftPadding: 2 * root.s
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 13 * root.s
                            placeholderText: "what's on"
                            Accessible.name: "Event title"
                            placeholderTextColor: root.wxFaint
                            selectByMouse: true
                            selectionColor: Colors.primary
                            onTextChanged: { editor.titleVal = text; editor.autoRecur(); }
                            Keys.onReturnPressed: editor.commit()
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: root.wxFaint
                            opacity: titleField.activeFocus ? 0.7 : 0.2
                            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                        }
                    }

                    Rectangle {
                        id: addBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28 * root.s
                        height: 28 * root.s
                        radius: Motion.rSmall * root.s
                        readonly property bool armed: editor.titleVal.trim().length > 0
                        color: addArea.containsMouse && armed ? Qt.alpha(Colors.tertiary, 0.22)
                            : (armed ? Qt.alpha(Colors.tertiary, 0.12) : Colors.surface_container_highest)
                        border.width: 1
                        border.color: armed ? Qt.alpha(Colors.tertiary, 0.5) : Qt.alpha(Colors.outline_variant, 0.9)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        Accessible.role: Accessible.Button
                        Accessible.name: "Add event"
                        Accessible.description: addBtn.armed ? "" : "Enter a title first"
                        Accessible.focusable: true
                        Accessible.onPressAction: editor.commit()

                        scale: addArea.pressed ? 0.92 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: addBtn.armed ? Colors.tertiary : Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 18 * root.s
                            font.weight: Font.Medium
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        MouseArea {
                            id: addArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: editor.commit()
                        }
                    }
                }

                Seg {
                    options: [
                        { label: "All day", value: "allday" },
                        { label: "Timed", value: "timed" }
                    ]
                    value: editor.mode
                    onPicked: (v) => editor.mode = v
                }

                Row {
                    width: parent.width
                    spacing: 8 * root.s
                    visible: editor.mode === "timed"

                    Item {
                        width: (parent.width - 8 * root.s) / 2
                        height: 26 * root.s

                        TextField {
                            id: startField
                            anchors.fill: parent
                            background: null
                            padding: 0
                            leftPadding: 2 * root.s
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 13 * root.s
                            font.features: ({ "tnum": 1 })
                            placeholderText: "09:00"
                            Accessible.name: "Start time"
                            placeholderTextColor: root.wxFaint
                            inputMethodHints: Qt.ImhPreferNumbers
                            selectByMouse: true
                            selectionColor: Colors.primary
                            onTextChanged: editor.startVal = text
                            Keys.onReturnPressed: editor.commit()
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: root.wxFaint
                            opacity: startField.activeFocus ? 0.7 : 0.2
                            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                        }
                    }

                    Item {
                        width: (parent.width - 8 * root.s) / 2
                        height: 26 * root.s

                        TextField {
                            id: endField
                            anchors.fill: parent
                            background: null
                            padding: 0
                            leftPadding: 2 * root.s
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.on_surface
                            font.family: Appearance.font.family
                            font.pixelSize: 13 * root.s
                            font.features: ({ "tnum": 1 })
                            placeholderText: "until"
                            Accessible.name: "End time"
                            placeholderTextColor: root.wxFaint
                            inputMethodHints: Qt.ImhPreferNumbers
                            selectByMouse: true
                            selectionColor: Colors.primary
                            onTextChanged: editor.endVal = text
                            Keys.onReturnPressed: editor.commit()
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: root.wxFaint
                            opacity: endField.activeFocus ? 0.7 : 0.2
                            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
                        }
                    }
                }

                Seg {
                    options: [
                        { label: "Once", value: "" },
                        { label: "Monthly", value: "month" },
                        { label: "Yearly", value: "year" }
                    ]
                    value: editor.recur
                    onPicked: (v) => {
                        editor.recurManual = true;
                        editor.recur = v;
                        if (v !== "") {
                            root.selEndDate = "";
                            root.pickingEnd = false;
                        }
                    }
                }

                /**
                 * Span control: the chip shows the day or range, the button arms
                 * the grid so the next day click closes a span (the under-grid
                 * hint and range tint guide it), and ✕ drops a set span back to
                 * a single day. Hidden for a recurring entry, which is a single
                 * repeating day.
                 */
                Row {
                    width: parent.width
                    spacing: 8 * root.s
                    visible: editor.recur === ""

                    Rectangle {
                        id: spanChip
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - extendBtn.width - clearSpan.width - 16 * root.s
                        height: 28 * root.s
                        radius: Motion.rSmall * root.s
                        color: Colors.surface_container_highest
                        border.width: 1
                        border.color: Qt.alpha(Colors.outline_variant, 0.9)

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 9 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7 * root.s

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 9 * root.s
                                height: 9 * root.s
                                radius: 3 * root.s
                                color: Colors.tertiary
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: editor.spanLabel
                                color: root.selEndDate.length > 0 ? Colors.on_surface : Colors.on_surface_variant
                                font.family: Appearance.font.family
                                font.pixelSize: 11 * root.s
                                font.weight: Font.Medium
                                font.features: ({ "tnum": 1 })
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                        }
                    }

                    Rectangle {
                        id: extendBtn
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool armed: root.pickingEnd
                        width: extendLabel.implicitWidth + 18 * root.s
                        height: 28 * root.s
                        radius: Motion.rSmall * root.s
                        color: armed ? Qt.alpha(Colors.tertiary, 0.14) : Colors.surface_container_highest
                        border.width: 1
                        border.color: armed ? Qt.alpha(Colors.tertiary, 0.5) : Qt.alpha(Colors.outline_variant, 0.9)
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        Accessible.role: Accessible.Button
                        Accessible.name: root.pickingEnd ? "Picking end day"
                            : (root.selEndDate.length > 0 ? "Edit date range" : "Extend to multiple days")
                        Accessible.checkable: true
                        Accessible.checked: extendBtn.armed
                        Accessible.focusable: true
                        Accessible.onPressAction: {
                            if (root.pickingEnd) {
                                root.pickingEnd = false;
                                root.hoverDay = 0;
                            } else {
                                root.selEndDate = "";
                                root.pickingEnd = true;
                            }
                        }

                        scale: extendArea.pressed ? 0.92 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        Text {
                            id: extendLabel
                            anchors.centerIn: parent
                            text: root.pickingEnd ? "pick…" : (root.selEndDate.length > 0 ? "edit" : "+ days")
                            color: extendBtn.armed ? Colors.tertiary : Colors.on_surface_variant
                            font.family: Appearance.font.family
                            font.pixelSize: 10.5 * root.s
                            font.weight: Font.Bold
                            font.letterSpacing: 0.3 * root.s
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }

                        MouseArea {
                            id: extendArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.pickingEnd) {
                                    root.pickingEnd = false;
                                    root.hoverDay = 0;
                                } else {
                                    root.selEndDate = "";
                                    root.pickingEnd = true;
                                }
                            }
                        }
                    }

                    Item {
                        id: clearSpan
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? 16 * root.s : 0
                        height: 16 * root.s
                        visible: root.selEndDate.length > 0 && !root.pickingEnd

                        Accessible.role: Accessible.Button
                        Accessible.name: "Clear date range"
                        Accessible.focusable: clearSpan.visible
                        Accessible.onPressAction: root.selEndDate = ""

                        scale: clearArea.pressed ? 0.92 : 1
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.glide
                                easing.type: Motion.easeBezier
                                easing.bezierCurve: Motion.expressiveFastSpatial
                            }
                        }

                        GlyphIcon {
                            anchors.fill: parent
                            name: "close"
                            color: clearArea.containsMouse ? Colors.tertiary : Colors.on_surface_variant
                            stroke: 1.6
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            anchors.margins: -5 * root.s
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selEndDate = ""
                        }
                    }
                }
            }
        }
    }
}
