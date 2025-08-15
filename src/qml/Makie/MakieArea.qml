import QtQml
import QtQuick
import QtQuick.Window
import jlqml

MakieViewport {

  // Factor by which to multiply the wheel angle to obtain a number of pixels of motion
  property real wheelfactor: 0.1

  Component.onCompleted: {
    Julia.dpi_changed(scene, Screen.pixelDensity);
    Julia.set_focus(scene, activeFocus)
  }

  onActiveFocusChanged: Julia.set_focus(scene, activeFocus)

  Connections {
    target: parent.Screen
    function onPixelDensityChanged() { Julia.dpi_changed(scene, Screen.pixelDensity); }
  }

  Connections {
    target: parent.Window.window
    function onClosing() { Julia.on_window_close(scene); }
  }

  TapHandler {
    id: tapHandler
    
    onTapped: {
      if(!parent.activeFocus) {
        parent.forceActiveFocus(Qt.MouseFocusReason);
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    visible: parent.activeFocus
    cursorShape: Qt.CrossCursor
    hoverEnabled: true
    onContainsMouseChanged: Julia.set_entered_window(scene, containsMouse)
    onPressed: (mouseEvent) => Julia.on_mouse_pressed(scene, mouseEvent.button)
    onPressedButtonsChanged: Julia.set_pressed_buttons(scene, pressedButtons)
    onMouseXChanged: Julia.on_mouse_moved(scene, mouseX, mouseY)
    onMouseYChanged: Julia.on_mouse_moved(scene, mouseX, mouseY)
    onWheel: (wheelEvent) => Julia.on_wheel(scene, wheelEvent.angleDelta.x, wheelEvent.angleDelta.y, wheelEvent.pixelDelta.x, wheelEvent.pixelDelta.y, parent.wheelfactor)
  }

  Keys.onPressed: (event) => Julia.on_key_pressed(scene, event.key, event.text, event.isAutoRepeat)
  Keys.onReleased: (event) => Julia.on_key_released(scene, event.key)

  DropArea {
    anchors.fill: parent
    onDropped: (event) => {
      if(event.hasUrls) {
        Julia.on_files_dropped(scene, event.urls)
      }
    }
  }
}