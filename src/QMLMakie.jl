module QMLMakie

using GLMakie
using CxxWrap
using QML
using ModernGL
using Observables

function __init__()
  QML.define_julia_module_makie(QMLMakie)
end

mutable struct QMLGLContext
  valid::Bool
  fbo::CxxPtr{QML.QOpenGLFramebufferObject}
end

@cxxdereference function sizetuple(fbo::QML.QOpenGLFramebufferObject)
  fbosize = QML.size(fbo)
  return (Int(QML.width(fbosize)), Int(QML.height(fbosize)))
end

mutable struct QMLWindow
  context::QMLGLContext
  window_area::Observable{Rect2i}
  qml_postprocessor::GLMakie.PostProcessor

  @cxxdereference function QMLWindow(fbo::QML.QOpenGLFramebufferObject)
    ctx = QMLGLContext(true, CxxPtr(fbo))
    win = new(ctx, Rect2i(0,0,0,0))
    return win
  end
end

qmlwindow(screen::GLMakie.Screen{QMLWindow}) = screen.glscreen

function setup_screen(screen, fbo)
  win = qmlwindow(screen)
  win.context.fbo = fbo
  win.window_area[] = Rect2i(0,0,sizetuple(fbo)...)
  return screen
end

function setup_screen(fbo)
  try
    screen = GLMakie.Screen(; window=QMLWindow(fbo), start_renderloop=false)
    return setup_screen(screen, fbo)
  catch exc
    showerror(stdout, exc, catch_backtrace())
    println(stdout)
  end
end

function GLMakie.ShaderAbstractions.native_switch_context!(win::QMLWindow)
  ctx = win.context
  if !ctx.valid
    try
      error("Attempt to bind invalid context $ctx")
    catch e
      Base.printstyled("ERROR: "; color=:red, bold=true)
      Base.showerror(stdout, e)
      Base.show_backtrace(stdout, Base.catch_backtrace())
    end
  end
end

function GLMakie.ShaderAbstractions.native_context_alive(win::QMLWindow)
  return win.context.valid
end

function GLMakie.was_destroyed(win::QMLMakie.QMLWindow)
  return !win.context.valid
end

Base.isopen(screen::QMLWindow) = true
GLMakie.destroy!(::QMLWindow) = nothing
GLMakie.reopen!(screen::GLMakie.Screen{QMLWindow}) = screen
GLMakie.set_screen_visibility!(screen::GLMakie.Screen{QMLWindow}, visible::Bool) = nothing
GLMakie.set_title!(screen::GLMakie.Screen{QMLWindow}, title::String) = nothing

GLMakie.scale_factor(::QMLWindow) = 1.0 # TODO: Get the actual scale factor

function Makie.connect_screen(scene::Scene, screen::GLMakie.Screen{QMLWindow})
  connect!(scene.events.window_area, qmlwindow(screen).window_area)
  return
end

function Makie.disconnect_screen(scene::Scene, screen::GLMakie.Screen{QMLWindow})
  # TODO disconnect events here
  return
end

function Base.display(screen::GLMakie.Screen{QMLWindow}, scene::Scene)
  invoke(Base.display, Tuple{GLMakie.Screen,Scene}, screen, scene)
  GLMakie.pollevents(screen, Makie.RegularRenderTick)
  GLMakie.poll_updates(screen)
  GLMakie.render_frame(screen)
  
  win = qmlwindow(screen)
  w,h = win.window_area[].widths

  # Bind the QML FBO for drawing
  QML.bind(win.context.fbo)
  # Bind FBO 0 (used by GLMakie by default) as source
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0)
  # Copy the GLMakie color buffer to QML
  glBlitFramebuffer(0, 0, w, h,
                  0, 0, w, h,
                  GL_COLOR_BUFFER_BIT, GL_NEAREST)

  return
end

function on_context_destroy()
  return
end

end # module QMLMakie
