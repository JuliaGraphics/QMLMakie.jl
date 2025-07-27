ENV["QSG_RENDER_LOOP"] = "basic"

using GLMakie
set_theme!(theme_black())

using CxxWrap
using QML
using QMLMakie
QML.setGraphicsApi(QML.OpenGL)


Base.@kwdef mutable struct Lorenz
  frame::Int64 = 0
  dt::Float64 = 0.001
  σ::Float64 = 10
  ρ::Float64 = 28
  β::Float64 = 8 / 3
  x::Float64 = 1
  y::Float64 = 1
  z::Float64 = 1
end

function step!(l::Lorenz)
  dx = l.σ * (l.y - l.x)
  dy = l.x * (l.ρ - l.z) - l.y
  dz = l.x * l.y - l.β * l.z
  l.x += l.dt * dx
  l.y += l.dt * dy
  l.z += l.dt * dz
  Point3f(l.x, l.y, l.z)
end

const QML_SRC = QByteArray("""
import QtQuick
import QtQuick.Controls
import jlqml

ApplicationWindow {
  title: "Test"
  visible: true
  width: 400
  height: 400

  MakieViewport {
    id: lorenz
    anchors.fill: parent
    renderFunction: redraw
  }

  Button {
    text: tick.running? "Pause" : "Play"
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    onClicked: tick.running = !tick.running
  }

  Timer {
    id: tick
    interval: 8
    running: true
    repeat: true
    onTriggered: {
      Julia.step()
      lorenz.update()
    }
  }
}
""")

const attractor = Lorenz()
const points = Observable(Point3f[])
const colors = Observable(Int[])

fig, ax, l = lines(points, color=colors,
  colormap=:inferno, transparency=true,
  axis=(; type=Axis3, protrusions=(0, 0, 0, 0),
    viewmode=:fit, limits=(-30, 30, -30, 30, 0, 50)))

function step!()
  for i in 1:20
    push!(points[], step!(attractor))
    push!(colors[], attractor.frame)
  end
  ax.azimuth[] = 1.7pi + 0.3 * sin(2pi * attractor.frame / 1200)
  notify(points)
  notify(colors)
  l.colorrange = (0, attractor.frame)
  attractor.frame += 1
end

const QT_ENGINE = init_qmlengine()

redraw(screen) = display(screen, fig.scene)

ctx = root_context(QT_ENGINE)
set_context_property(ctx, "redraw", @safe_cfunction(redraw, Cvoid, (Any,)))
QML.qmlfunction("step", step!)

qcomp = QQmlComponent(QT_ENGINE)
set_data(qcomp, QML_SRC, QML.QUrl())
create(qcomp, qmlcontext())

exec()
