import QtQuick
import QtQuick.Controls
import "../colors"
import "../services"
import "../config"

/**
 * astralis — surface search input (ported from Ricelin SearchField.qml): a
 * kanji prefix, a filled pill field (outline lights on focus) holding the
 * input and a live "n / total" counter, and a default right-content slot.
 * The Ame bead is the caret, so the placeholder sits one bead-width in from
 * the caret instead of under it. Up/Down (and
 * Left/Right with `horizontalNav`) emit moved(), Enter accepted(), Escape
 * dismissed(). Callers reach the raw input through the `input` alias for
 * focus handling.
 */
Item {
    id: root

    property real s: 1
    property string kanji: ""
    property string placeholder: ""

    /** Either bind `count`/`total`, or bind `counterText` directly. */
    property int count: -1
    property int total: -1
    property string counterText: count >= 0 && total >= 0 ? count + " / " + total : ""

    /**
     * Map Left/Right to the moved() signal instead of text-cursor motion. For a
     * horizontal result strip the arrows should page the strip; without this the
     * field swallows them until the caret sits at a text boundary, so navigation
     * stalls mid-query.
     */
    property bool horizontalNav: false
    readonly property alias input: field
    property alias text: field.text
    default property alias rightContent: rightSlot.data

    signal moved(int delta)
    signal accepted()
    signal dismissed()
    signal keyPressed(var event)

    height: 34 * s

    TextMetrics {
        id: glyphMetrics
        text: root.kanji
        font.family: Appearance.font.jp
        font.weight: Font.Medium
        font.pixelSize: 16 * root.s
    }

    Text {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        visible: Flags.showGlyphs
        // Collapse the reserved width when hidden so the field reclaims the gap
        // instead of indenting behind an invisible glyph.
        //
        // Measured off a TextMetrics rather than off this Text's own
        // `implicitWidth`: a Text whose width is bound to its own implicit
        // width is a binding loop ("Binding loop detected for property width"),
        // because implicit width is derived from the layout that width feeds.
        width: visible ? glyphMetrics.advanceWidth : 0
        text: root.kanji
        color: Colors.on_surface_variant
        font.family: Appearance.font.jp
        font.weight: Font.Medium
        font.pixelSize: 16 * root.s
    }

    Rectangle {
        id: box
        anchors.left: glyph.right
        anchors.leftMargin: glyph.visible ? 10 * root.s : 0
        anchors.right: rightSlot.left
        anchors.rightMargin: rightSlot.width > 0 ? 8 * root.s : 0
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        // Concentric with the open pill's 22 corner at the surfaces' ~11
        // inset, one step above the 9-radius result rows: a full capsule here
        // ran a different curve from the corner wrapped around it.
        radius: 11 * root.s
        color: Colors.surface_container_high
        border.width: 1.2 * root.s
        border.color: field.activeFocus ? Qt.alpha(Colors.primary, 0.55) : Qt.alpha(Colors.on_surface, 0.06)
        Behavior on border.color { ColorAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }

    TextField {
        id: field
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: box.left
        anchors.leftMargin: 14 * root.s
        anchors.right: counter.left
        anchors.rightMargin: 10 * root.s
        background: null
        padding: 0
        color: Colors.on_surface
        font.family: Appearance.font.family
        font.pixelSize: 14 * root.s
        selectByMouse: true
        selectionColor: Qt.alpha(Colors.primary, 0.45)
        cursorDelegate: Item {}
        Keys.onUpPressed: root.moved(-1)
        Keys.onDownPressed: root.moved(1)
        Keys.onPressed: (e) => {
            root.keyPressed(e);
            if (e.accepted)
                return;
            if (root.horizontalNav && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
                root.moved(e.key === Qt.Key_Right ? 1 : -1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.accepted();
                e.accepted = true;
            } else if (e.key === Qt.Key_Escape) {
                root.dismissed();
                e.accepted = true;
            }
        }
    }

    // Own placeholder: TextField's sits at x 0, exactly where the bead caret
    // parks on an empty query, so the first letter hid behind it.
    Text {
        anchors.left: field.left
        anchors.leftMargin: 8 * root.s
        anchors.right: field.right
        anchors.verticalCenter: field.verticalCenter
        visible: field.text.length === 0 && field.preeditText.length === 0
        text: root.placeholder
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font: field.font
        elide: Text.ElideRight
    }

    // Centred on the digits' ink, not the line box: the box includes descender
    // space, so a plain verticalCenter rode the numerals above the trailing icon.
    FontMetrics {
        id: counterMetrics
        font: counter.font
    }

    Text {
        id: counter
        readonly property rect ink: counterMetrics.tightBoundingRect("0")
        anchors.baseline: parent.verticalCenter
        anchors.baselineOffset: -(ink.y + ink.height / 2)
        anchors.right: box.right
        anchors.rightMargin: 14 * root.s
        text: root.counterText
        color: Qt.alpha(Colors.on_surface_variant, 0.65)
        font.family: Appearance.font.family
        font.pixelSize: 10.5 * root.s
        font.features: ({ "tnum": 1 })
    }

    Item {
        id: rightSlot
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: childrenRect.width
        height: parent.height
    }
}
