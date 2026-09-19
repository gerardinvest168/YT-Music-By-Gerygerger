import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

// Two backends, one chip.
//
// MPRIS is the default and still covers Spotify and YTMDesktop 1.x. YTMDesktop
// 2.x ships no MPRIS at all, so when a companion-server token is present next to
// this plugin we also poll its local HTTP API. The backend that actually has a
// playing track wins; if neither plays, whichever has a loaded track wins, and
// otherwise we fall back to MPRIS untouched.
//
// The HTTP side shells out to curl rather than using XMLHttpRequest, the same
// way the stock weather widget does, so no cross-origin handling is involved.
BarWidget {
  id: root
  moduleName: "gerygerger.ytmusic"

  property bool opened: false
  property bool popoutSwitchClosing: false

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: pickYouTubeMusic()

  readonly property string baseUrl: "http://127.0.0.1:9863/api/v1"
  readonly property string tokenPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/gerygerger.ytmusic/ytmdesktop-token"

  property string token: ""
  property var ytdState: null
  property int ytdFailures: 0

  // Set by a click so the chip reacts immediately; the app acks on a later
  // poll, and the override is released once the server agrees or it goes stale.
  property var playingOverride: null

  readonly property bool ytdEnabled: token !== ""
  readonly property var ytdPlayer: ytdState && ytdState.player ? ytdState.player : null
  readonly property var ytdVideo: ytdState && ytdState.video ? ytdState.video : null
  readonly property bool ytdHasTrack: !!(ytdVideo && (ytdVideo.title || ytdVideo.author))
  // The app's PlaybackState enum: -1 unknown, 0 paused, 1 playing, 2 buffering.
  // It ships as a bare number in the state payload, so treat buffering as playing.
  readonly property bool ytdPlaying: {
    const state = ytdPlayer ? ytdPlayer.trackState : -1
    return state === 1 || state === 2
  }

  readonly property bool mprisHasTrack: !!(player && (player.trackTitle || player.trackArtist))
  readonly property bool mprisPlaying: player ? !!player.isPlaying : false

  readonly property bool usingYtd: {
    if (ytdHasTrack && ytdPlaying)
      return true
    if (mprisHasTrack && mprisPlaying)
      return false
    return ytdHasTrack
  }

  onUsingYtdChanged: playingOverride = null

  readonly property bool hasTrack: ytdHasTrack || mprisHasTrack
  readonly property bool playing: playingOverride !== null ? playingOverride : (usingYtd ? ytdPlaying : mprisPlaying)
  readonly property bool isAd: {
    if (usingYtd)
      return !!(ytdPlayer && ytdPlayer.adPlaying)
    if (!player)
      return false
    const trackId = player.trackId || player.dbusName || ""
    if (String(trackId).indexOf(":ad:") !== -1)
      return true
    const title = String(player.trackTitle || "").toLowerCase()
    return title.indexOf("advertisement") !== -1
  }
  readonly property string artist: usingYtd ? String(ytdVideo.author || "") : (player ? (player.trackArtist || "") : "")
  readonly property string title: usingYtd ? String(ytdVideo.title || "") : (player ? (player.trackTitle || "") : "")
  readonly property string displayText: {
    if (isAd)
      return "Advertisement"
    if (artist && title)
      return artist + " - " + title
    return title || artist
  }
  // At most maxChars characters are visible at once; anything longer scrolls
  // through the clipped window rather than being cut off. Tunable from this
  // widget's entry in shell.json.
  readonly property int maxChars: {
    const configured = Number(setting("maxChars", 20))
    return isNaN(configured) || configured < 4 ? 20 : Math.floor(configured)
  }
  readonly property string windowText: displayText.slice(0, maxChars)
  readonly property bool scrolling: displayText.length > maxChars

  readonly property color chipForeground: bar ? bar.barForeground : Color.foreground
  readonly property string chipFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real horizontalMargin: Style.spaceReal(8.5)
  readonly property real iconGap: Style.space(5)

  visible: hasTrack
  implicitWidth: hasTrack ? contentRow.implicitWidth + horizontalMargin * 2 : 0
  implicitHeight: button.implicitHeight

  onScrollingChanged: if (!scrolling) marqueeText.x = 0

  function open() {}
  function close() {}
  function toggle() {}
  function closeForPopoutSwitch() {}

  function looksLikeYouTubeMusic(p) {
    if (!p)
      return false
    const blob = [
      p.identity || "",
      p.desktopEntry || "",
      p.dbusName || "",
      p.busName || ""
    ].join(" ").toLowerCase()
    const keys = [
      "youtube music",
      "youtube-music",
      "youtubemusic",
      "youtube_music",
      "ytmusic",
      "ytmdesktop",
      "youtube"
    ]
    for (let i = 0; i < keys.length; i++) {
      if (blob.indexOf(keys[i]) !== -1)
        return true
    }
    return false
  }

  function pickYouTubeMusic() {
    const list = players || []
    for (let i = 0; i < list.length; i++) {
      if (looksLikeYouTubeMusic(list[i]))
        return list[i]
    }
    return null
  }

  function pollState() {
    if (!ytdEnabled || stateProc.running || cmdProc.running)
      return
    stateProc.command = ["curl", "-fsS", "--max-time", "4",
                         "-H", "Authorization: " + token,
                         baseUrl + "/state"]
    stateProc.running = true
  }

  function sendCommand(name) {
    if (!ytdEnabled)
      return false
    cmdProc.command = ["curl", "-fsS", "--max-time", "4", "-X", "POST",
                       "-H", "Authorization: " + token,
                       "-H", "Content-Type: application/json",
                       "-d", JSON.stringify({ command: name }),
                       baseUrl + "/command"]
    cmdProc.running = true
    return true
  }

  function applyState(raw) {
    const text = String(raw || "").trim()
    if (!text) {
      // curl failed, so the app is closed or the token was revoked. Clear on the
      // second miss so one hiccup does not blink the chip away.
      ytdFailures++
      if (ytdFailures >= 2) {
        ytdState = null
        ytdFailures = 0
      }
      return
    }
    try {
      ytdState = JSON.parse(text)
      ytdFailures = 0
      if (playingOverride !== null && ytdPlaying === playingOverride)
        playingOverride = null
    } catch (e) {
      ytdFailures++
    }
  }

  function playPause() {
    if (usingYtd) {
      playingOverride = !playing
      overrideTimer.restart()
      if (sendCommand("playPause"))
        return
    }
    if (!player)
      return
    if (player.isPlaying && player.canPause)
      player.pause()
    else if (!player.isPlaying && player.canPlay)
      player.play()
    else if (player.canTogglePlaying)
      player.togglePlaying()
  }

  function next() {
    if (usingYtd && sendCommand("next"))
      return
    if (player && player.canGoNext)
      player.next()
  }

  function previous() {
    if (usingYtd && sendCommand("previous"))
      return
    if (player && player.canGoPrevious)
      player.previous()
  }

  FileView {
    id: tokenFile
    path: root.tokenPath
    blockLoading: true
    printErrors: false
  }

  Component.onCompleted: {
    try {
      root.token = String(tokenFile.text() || "").trim()
    } catch (e) {
      root.token = ""
    }
  }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  Process {
    id: cmdProc
  }

  // /state is rate limited to one request per 5 seconds, so stay just above it.
  Timer {
    id: pollTimer
    interval: 6000
    repeat: true
    running: root.ytdEnabled
    onTriggered: root.pollState()
  }

  Timer {
    id: overrideTimer
    interval: 8000
    onTriggered: root.playingOverride = null
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Stays the bar's click surface and tooltip host; the visible chip is drawn
    // by the Row below so the label can scroll in a clipped window. Overriding
    // hasVisualContent keeps the button hit-testable with empty text.
    text: ""
    hasVisualContent: true
    tooltipText: root.hasTrack ? ((root.playing ? "Playing" : "Paused") + "\n" + root.displayText + "\n\nClick: play/pause · scroll: skip") : ""
    onPressed: function(buttonCode) {
      if (!root.hasTrack)
        return
      if (buttonCode === Qt.LeftButton)
        root.playPause()
      else if (buttonCode === Qt.MiddleButton)
        root.previous()
      else if (buttonCode === Qt.RightButton)
        root.next()
    }
    onWheelMoved: function(delta) {
      if (!root.hasTrack || delta === 0)
        return
      // Match Omarchy media widget: scroll up = previous, scroll down = next
      if (delta > 0)
        root.previous()
      else
        root.next()
    }
  }

  // Chip: YouTube mark, then a window one maxChars wide holding the label. It
  // draws above the button, and neither Text takes pointer input, so clicks and
  // the scroll wheel still land on the button underneath.
  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: root.iconGap

    Text {
      id: ytIcon
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "\uf16a"
      color: root.chipForeground
      font.family: root.chipFontFamily
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    Item {
      id: scrollClip
      anchors.verticalCenter: parent.verticalCenter
      width: windowMetrics.advanceWidth
      height: ytIcon.implicitHeight
      clip: true

      Text {
        id: marqueeText
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.displayText
        color: root.chipForeground
        font.family: root.chipFontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering

        // Same marquee Omarchy's own media widget uses. It only runs when the
        // label overflows the window, so short titles just sit still.
        NumberAnimation on x {
          running: root.scrolling
          loops: Animation.Infinite
          from: scrollClip.width
          to: -marqueeText.implicitWidth
          duration: Math.max(6000, marqueeText.implicitWidth * 25)
          easing.type: Easing.Linear
        }
      }
    }
  }

  TextMetrics {
    id: windowMetrics
    text: root.windowText
    font.family: root.chipFontFamily
    font.pixelSize: Style.font.body
  }
}
