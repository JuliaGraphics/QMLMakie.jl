import QtQml
import QtQuick
import QtQuick.Window
import jlqml

MakieViewport {

  // Factor by which to multiply the wheel angle to obtain a number of pixels of motion
  property real wheelfactor: 0.01

  Component.onCompleted: {
    Julia.dpi_changed(scene, Screen.pixelDensity, Window.window);
    Julia.set_focus(scene, activeFocus)
  }

  onActiveFocusChanged: { Julia.set_focus(scene, activeFocus); update() }

  Connections {
    target: parent.Screen
    function onPixelDensityChanged() { Julia.dpi_changed(scene, Screen.pixelDensity, parent.Window.window); parent.update(); }
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
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    visible: parent.activeFocus
    cursorShape: Qt.CrossCursor
    hoverEnabled: true

    function throttledmouse(mouseX, mouseY) {
      if(timer.count < 1)
      {
        timer.cached = true;
        timer.lastX = mouseX;
        timer.lastY = height-mouseY;
        return;
      }

      timer.count = 0;
      timer.cached = false;
      Julia.on_mouse_moved(scene, mouseX, height-mouseY);
      parent.update();

    }

    onContainsMouseChanged: { Julia.set_entered_window(scene, containsMouse); parent.update(); }
    onPressed: (mouseEvent) => { Julia.on_mouse_pressed(scene, mouseEvent.button); parent.update(); }
    onReleased: (mouseEvent) => { Julia.on_mouse_released(scene, mouseEvent.button); parent.update(); }
    onMouseXChanged: throttledmouse(mouseX, mouseY)
    onMouseYChanged: throttledmouse(mouseX, mouseY)
    onWheel: (wheelEvent) => {
      Julia.on_wheel(scene, wheelEvent.angleDelta.x, wheelEvent.angleDelta.y, wheelEvent.pixelDelta.x, wheelEvent.pixelDelta.y, parent.wheelfactor);
      parent.update();
    }
  }

  Keys.onPressed: (event) => { Julia.on_key_pressed(scene, event.key, event.text, event.isAutoRepeat); update(); }
  Keys.onReleased: (event) => { Julia.on_key_released(scene, event.key); update(); }

  DropArea {
    anchors.fill: parent
    onDropped: (event) => {
      if(event.hasUrls) {
        Julia.on_files_dropped(scene, event.urls);
        parent.update();
      }
    }
  }

  // The timer here is used to skip mouse position updates if they are less than 10 ms apart
  // Doing this improves the smoothness of e.g. panning.
  Timer {
    property int count: 0
    property bool cached: false
    property real lastX: 0
    property real lastY: 0

    id: timer
    interval: 10; running: true; repeat: true;
    onTriggered: {
      if(cached) {
        cached = false;
        Julia.on_mouse_moved(scene, lastX, lastY);
        parent.update();
      } else {
        count += 1;
      }
    }
  }
}