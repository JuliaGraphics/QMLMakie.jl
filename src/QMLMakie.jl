module QMLMakie

using GLMakie
using CxxWrap
using QML
using ModernGL
using Observables

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
  pixelratio::Float64
  window_area::Observable{Rect2i}
  fbo_size::Tuple{Int,Int}

  @cxxdereference function QMLWindow(fbo::QML.QOpenGLFramebufferObject, quickwin::CxxPtr{QML.QQuickWindow})
    ctx = QMLGLContext(true, CxxPtr(fbo))
    win = new(ctx, QML.effectiveDevicePixelRatio(quickwin), Rect2i(0,0,0,0), (0,0))
    return win
  end
end

qmlwindow(screen::GLMakie.Screen{QMLWindow}) = screen.glscreen

function setup_screen(screen::GLMakie.Screen, fbo)
  win = qmlwindow(screen)
  win.context.fbo = fbo
  win.fbo_size = sizetuple(fbo)
  win.window_area[] = Rect2i(0,0,round.(win.fbo_size ./ win.pixelratio)...)
  return screen
end

function setup_screen(fbo, quickwin::CxxPtr{QML.QQuickWindow})
  try
    screen = GLMakie.Screen(; window=QMLWindow(fbo, quickwin), start_renderloop=false)
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

GLMakie.scale_factor(win::QMLWindow) = win.pixelratio

function Makie.connect_screen(scene::Scene, screen::GLMakie.Screen{QMLWindow})
  connect!(scene.events.window_area, qmlwindow(screen).window_area)
  return
end

function Makie.disconnect_screen(scene::Scene, screen::GLMakie.Screen{QMLWindow})
  qmlwin = qmlwindow(screen)
  Observables.clear(qmlwin.window_area)
  return
end

function Base.display(screen::GLMakie.Screen{QMLWindow}, scene::Scene)
  invoke(Base.display, Tuple{GLMakie.Screen,Scene}, screen, scene)
  GLMakie.pollevents(screen, Makie.RegularRenderTick)
  GLMakie.poll_updates(screen)
  GLMakie.render_frame(screen)

  win = qmlwindow(screen)

  # Up to a potential rounding error, both of these should be the same
  wmakie,hmakie = screen.framebuffer.resolution[]
  wqml, hqml = win.fbo_size

  # Bind the QML FBO for drawing
  QML.bind(win.context.fbo)
  # Bind FBO 0 (used by GLMakie by default) as source
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0)
  # Copy the GLMakie color buffer to QML
  glBlitFramebuffer(0, 0, wmakie, hmakie,
                  0, 0, wqml, hqml,
                  GL_COLOR_BUFFER_BIT, GL_LINEAR)

  return
end

function on_context_destroy(screen)
  return
end

function renderfunction(screen::GLMakie.Screen{QMLWindow}, sceneorfigure)
  scene = Makie.get_scene(sceneorfigure)
  if !Makie.is_displayed(screen, scene)
    # This makes sure the axis is autoscaled as it is in the regular Makie
    Makie.update_state_before_display!(sceneorfigure)
  end
  display(screen, scene)
  # Since the cfunction call specifies void, it is important that the renderfunction doesn't return anything.
  return
end

function seteventvalue(::Nothing, eventname, _)
  @warn "No scene is defined for the MakieArea. Set the scene property  in QML to pass  on events. Ignoring event $eventname"
end

function seteventvalue(scene, eventname, value)
  events = Makie.events(scene)
  eventproperty = getproperty(events, eventname)
  #println("setting $eventname to $value")
  eventproperty[] = value
end

const qt_to_makie_buttons = (
  NoButton      = Makie.Mouse.none,
  LeftButton    = Makie.Mouse.left,
  RightButton   = Makie.Mouse.right,
  MiddleButton  = Makie.Mouse.middle,
  BackButton    = Makie.Mouse.button_4,
  ForwardButton = Makie.Mouse.button_5,
  TaskButton    = Makie.Mouse.button_6,
  ExtraButton4  = Makie.Mouse.button_7,
  ExtraButton5  = Makie.Mouse.button_8,
)

# Map a qt button code to the corresponding Makie code
function qtbutton_to_makie(qtbutton)
  try
    makiebutton = qt_to_makie_buttons[Symbol(qtbutton)]
    return getproperty(Makie.Mouse, Symbol(makiebutton))
  catch e
    @warn "Can't convert Qt buton $qtbutton, returning none"
    return Makie.Mouse.none
  end
end

# pixeldensity is in dots per mm, so we need to convert to dpi
dpi_changed(scene, pixeldensity) = seteventvalue(scene, :window_dpi, pixeldensity*25.4)
on_window_close(scene) = seteventvalue(scene, :window_open, false)
set_focus(scene, focus) = seteventvalue(scene, :hasfocus, focus)
set_entered_window(scene, inwindow) = seteventvalue(scene, :entered_window, inwindow)
function on_mouse_pressed(scene, buttonint)
  button = QML.MouseButton(buttonint)
  action = Makie.Mouse.press
  event = Makie.MouseButtonEvent(qtbutton_to_makie(button), action)
  seteventvalue(scene, :mousebutton, event)
end

function set_pressed_buttons(scene, buttons)
  events = Makie.events(scene)
  empty!(events.mousebuttonstate)
  for b in instances(QML.MouseButton)
    if (b != QML.NoButton) && ((buttons & Integer(b)) == Integer(b)) 
      push!(events.mousebuttonstate, qtbutton_to_makie(b))
    end
  end
  println("setting mousebuttonstate to ", events.mousebuttonstate)
end

on_mouse_moved(scene, x, y) = seteventvalue(scene, :mouseposition, (x,y))
function on_wheel(scene, anglex, angley, pixelx, pixely, wheelfactor)
  if pixelx == pixely == 0
    pixelx = anglex*wheelfactor
    pixely = angley*wheelfactor
  end
  seteventvalue(scene, :scroll, (pixelx, pixely))
end

function qtkey_to_makie(qtkey)
  if qtkey > 127
    try
      qtkeyenum = QML.Key(qtkey)
      qtkeyenum == QML.Key_Escape && return Makie.Keyboard.escape
      qtkeyenum == QML.Key_Enter && return Makie.Keyboard.enter
      qtkeyenum == QML.Key_Return && return Makie.Keyboard.enter
      qtkeyenum == QML.Key_Tab && return Makie.Keyboard.tab
      qtkeyenum == QML.Key_Backspace && return Makie.Keyboard.backspace
      qtkeyenum == QML.Key_Insert && return Makie.Keyboard.insert
      qtkeyenum == QML.Key_Delete && return Makie.Keyboard.delete
      qtkeyenum == QML.Key_Right && return Makie.Keyboard.right
      qtkeyenum == QML.Key_Left && return Makie.Keyboard.left
      qtkeyenum == QML.Key_Down && return Makie.Keyboard.down
      qtkeyenum == QML.Key_Up && return Makie.Keyboard.up
      qtkeyenum == QML.Key_PageUp && return Makie.Keyboard.page_up
      qtkeyenum == QML.Key_PageDown && return Makie.Keyboard.page_down
      qtkeyenum == QML.Key_Home && return Makie.Keyboard.home
      qtkeyenum == QML.Key_End && return Makie.Keyboard._end
      qtkeyenum == QML.Key_Alt && return Makie.Keyboard.left_alt
      qtkeyenum == QML.Key_AltGr && return Makie.Keyboard.right_alt
      qtkeyenum == QML.Key_Control && return Makie.Keyboard.left_control
      qtkeyenum == QML.Key_Shift && return Makie.Keyboard.left_shift
      qtkeyenum == QML.Key_Meta && return Makie.Keyboard.left_super
      qtkeyenum == QML.Key_Menu && return Makie.Keyboard.right_super
      @warn "not converting Qt key $qtkeyenum"
      return Makie.Keyboard.unknown
    catch
      @warn "Unknown Qt key code: $qtkey"
      return Makie.Keyboard.unknown
    end
  end
  
  return Makie.Keyboard.Button(qtkey)
end

function on_key_pressed(scene, qtkey, text, autorepeat)
  action = autorepeat ? Makie.Keyboard.repeat : Makie.Keyboard.press
  key = qtkey_to_makie(qtkey)
  push!(Makie.events(scene).keyboardstate, key)
  @show Makie.events(scene).keyboardstate
  seteventvalue(scene, :keyboardbutton, Makie.KeyEvent(key, action))
  if !isempty(text)
    seteventvalue(scene, :unicode_input, String(text)[1])
  end
end

function on_key_released(scene, qtkey)
  key = qtkey_to_makie(qtkey)
  delete!(Makie.events(scene).keyboardstate, key)
  @show Makie.events(scene).keyboardstate
  seteventvalue(scene, :keyboardbutton, Makie.KeyEvent(key, Makie.Keyboard.release))
end

function on_files_dropped(scene, urls)
  filepaths = map(u -> String(QML.toString(u))[8:end], urls)
  seteventvalue(scene, :dropped_files, filepaths)
end

function register_event_handlers()
  @qmlfunction dpi_changed
  @qmlfunction on_window_close
  @qmlfunction set_focus
  @qmlfunction set_entered_window
  @qmlfunction on_mouse_pressed
  @qmlfunction set_pressed_buttons
  @qmlfunction on_mouse_moved
  @qmlfunction on_wheel
  @qmlfunction on_key_pressed
  @qmlfunction on_key_released
  @qmlfunction on_files_dropped
end

function __init__()
  QML.define_julia_module_makie(QMLMakie)
  global _render_cfunc = @safe_cfunction(renderfunction, Cvoid, (Any,Any))
  QML.set_default_makie_renderfunction(_render_cfunc)
  QML.add_import_path(joinpath(@__DIR__, "qml"))

  register_event_handlers()
end

end # module QMLMakie
