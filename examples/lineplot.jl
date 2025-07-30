# Example based on the first Makie tutorial at:
# https://docs.makie.org/stable/tutorials/getting-started

ENV["QSG_RENDER_LOOP"] = "basic"

using GLMakie
using QMLMakie
using QML

# Data
seconds = 0:0.1:2
measurements = [8.2, 8.4, 6.3, 9.5, 9.1, 10.5, 8.6, 8.2, 10.5, 8.5, 7.2,
        8.8, 9.7, 10.8, 12.5, 11.6, 12.1, 12.1, 15.1, 14.7, 13.1]

# Makie plotting commands
f = Figure()
ax = Axis(f[1, 1],
    title = "Experimental data and exponential fit",
    xlabel = "Time (seconds)",
    ylabel = "Value",
)
scatter!(ax, seconds, measurements, color = :tomato)
lines!(ax, seconds, exp.(seconds) .+ 7, color = :tomato, linestyle = :dash)

# Build the QML interface and display the plot
mktemp() do qmlfile,_
  qml = """
  import QtQuick
  import QtQuick.Controls
  import jlqml

  ApplicationWindow {
    title: "Makie plot"
    visible: true
    width: 640
    height: 480

    MakieViewport {
      anchors.fill: parent
      scene: plot
    }

  }
  """

  write(qmlfile, qml)
  loadqml(qmlfile; plot = f)
  exec()
end
