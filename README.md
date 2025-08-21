# QMLMakie
This is a Julia package for bridging
[Makie](https://docs.makie.org/stable/)
and Qt via [QML.jl](https://github.com/JuliaGraphics/QML.jl).
It allows embedding hardware-accelerated interactive plots in Qt applications.

## Quickstart

The following example simply shows the first [lineplot example](https://docs.makie.org/stable/tutorials/getting-started) from the Makie documentation in a QML window. It uses the `MakieViewport` QML component that is provided by QML.jl, and then sets the `scene` property of that component to the Makie figure, by passing it to a QML context property named `plot`.

```julia
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

```

## Features

* All [Makie events](https://docs.makie.org/stable/explanations/events) are linked to the corresponding events coming from QML
* Proper support for scaled displays