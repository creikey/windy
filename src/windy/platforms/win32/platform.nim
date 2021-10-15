import ../../common, windefs

const
  windowClassName = "WINDY0"

  WGL_DRAW_TO_WINDOW_ARB = 0x2001
  WGL_ACCELERATION_ARB = 0x2003
  WGL_SUPPORT_OPENGL_ARB = 0x2010
  WGL_DOUBLE_BUFFER_ARB = 0x2011
  WGL_PIXEL_TYPE_ARB = 0x2013
  WGL_COLOR_BITS_ARB = 0x2014
  WGL_DEPTH_BITS_ARB = 0x2022
  WGL_STENCIL_BITS_ARB = 0x2023
  WGL_FULL_ACCELERATION_ARB = 0x2027
  WGL_TYPE_RGBA_ARB = 0x202B

  WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091
  WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092
  WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126
  WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001
  # WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002
  WGL_CONTEXT_FLAGS_ARB = 0x2094
  # WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001
  WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002

type
  PlatformWindow* = ref object
    hWnd: HWND
    hdc: HDC
    hglrc: HGLRC

var
  initialized: bool
  windows*: seq[PlatformWindow]
  wglCreateContext: wglCreateContext
  wglDeleteContext: wglDeleteContext
  wglGetProcAddress: wglGetProcAddress
  wglGetCurrentDC: wglGetCurrentDC
  wglGetCurrentContext: wglGetCurrentContext
  wglMakeCurrent: wglMakeCurrent
  wglCreateContextAttribsARB: wglCreateContextAttribsARB
  wglChoosePixelFormatARB: wglChoosePixelFormatARB
  wglSwapIntervalEXT: wglSwapIntervalEXT

proc wstr*(str: string): string =
  let wlen = MultiByteToWideChar(
    CP_UTF8,
    0,
    str[0].unsafeAddr,
    str.len.int32,
    nil,
    0
  )
  result = newString(wlen * 2 + 1)
  discard MultiByteToWideChar(
    CP_UTF8,
    0,
    str[0].unsafeAddr,
    str.len.int32,
    cast[ptr WCHAR](result[0].addr),
    wlen
  )

proc registerWindowClass(windowClassName: string, wndProc: WNDPROC) =
  let windowClassName = windowClassName.wstr()

  var wc: WNDCLASSEXW
  wc.cbSize = sizeof(WNDCLASSEXW).UINT
  wc.style = CS_HREDRAW or CS_VREDRAW or CS_DBLCLKS
  wc.lpfnWndProc = wndProc
  wc.hInstance = GetModuleHandleW(nil)
  wc.hCursor = LoadCursorW(0, IDC_ARROW)
  wc.lpszClassName = cast[ptr WCHAR](windowClassName[0].unsafeAddr)
  wc.hIcon = LoadImageW(
    0,
    IDI_APPLICATION,
    IMAGE_ICON,
    0,
    0,
    LR_DEFAULTSIZE or LR_SHARED
  )

  if RegisterClassExW(wc.addr) == 0:
    raise newException(WindyError, "Error registering window class")

proc createWindow(
  windowClassName, title: string, x, y, w, h: int
): HWND =
  let
    windowClassName = windowClassName.wstr()
    title = title.wstr()

  result = CreateWindowExW(
    WS_EX_APPWINDOW,
    cast[ptr WCHAR](windowClassName[0].unsafeAddr),
    cast[ptr WCHAR](title[0].unsafeAddr),
    WS_OVERLAPPEDWINDOW,
    x.int32,
    y.int32,
    w.int32,
    h.int32,
    0,
    0,
    GetModuleHandleW(nil),
    nil
  )
  if result == 0:
    raise newException(WindyError, "Creating native window failed")

proc getDC(hWnd: HWND): HDC =
  result = GetDC(hWnd)
  if result == 0:
    raise newException(WindyError, "Error getting window DC")

proc makeContextCurrent(hdc: HDC, hglrc: HGLRC) =
  if wglMakeCurrent(hdc, hglrc) == 0:
    raise newException(WindyError, "Error activating OpenGL rendering context")

proc loadOpenGL() =
  let opengl = LoadLibraryA("opengl32.dll")
  if opengl == 0:
    raise newException(WindyError, "Loading opengl32.dll failed")

  wglCreateContext =
    cast[wglCreateContext](GetProcAddress(opengl, "wglCreateContext"))
  wglDeleteContext =
    cast[wglDeleteContext](GetProcAddress(opengl, "wglDeleteContext"))
  wglGetProcAddress =
    cast[wglGetProcAddress](GetProcAddress(opengl, "wglGetProcAddress"))
  wglGetCurrentDC =
    cast[wglGetCurrentDC](GetProcAddress(opengl, "wglGetCurrentDC"))
  wglGetCurrentContext =
    cast[wglGetCurrentContext](GetProcAddress(opengl, "wglGetCurrentContext"))
  wglMakeCurrent =
    cast[wglMakeCurrent](GetProcAddress(opengl, "wglMakeCurrent"))

  # Before we can load extensions, we need a dummy OpenGL context, created using
  # a dummy window. We use a dummy window because you can only set the pixel
  # format for a window once. For the real window, we want to use
  # wglChoosePixelFormatARB (so we can potentially specify options that aren't
  # available in PIXELFORMATDESCRIPTOR), but we can't load and use that before
  # we have a context.

  let dummyWindowClassName = "WindyDummy"

  proc dummyWndProc(
    hWnd: HWND, uMsg: UINT, wParam: WPARAM, lParam: LPARAM
  ): LRESULT {.stdcall.} =
    DefWindowProcW(hWnd, uMsg, wParam, lParam)

  registerWindowClass(dummyWindowClassName, dummyWndProc)

  let
    hWnd = createWindow(
      dummyWindowClassName,
      dummyWindowClassName,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      CW_USEDEFAULT,
      CW_USEDEFAULT
    )
    hdc = getDC(hWnd)

  var pfd: PIXELFORMATDESCRIPTOR
  pfd.nSize = sizeof(PIXELFORMATDESCRIPTOR).WORD
  pfd.nVersion = 1
  pfd.dwFlags = PFD_DRAW_TO_WINDOW or PFD_SUPPORT_OPENGL or PFD_DOUBLEBUFFER
  pfd.iPixelType = PFD_TYPE_RGBA
  pfd.cColorBits = 32
  pfd.cAlphaBits = 8
  pfd.cDepthBits = 24
  pfd.cStencilBits = 8

  let pixelFormat = ChoosePixelFormat(hdc, pfd.addr)
  if pixelFormat == 0:
    raise newException(WindyError, "Error choosing pixel format")

  if SetPixelFormat(hdc, pixelFormat, pfd.addr) == 0:
    raise newException(WindyError, "Error setting pixel format")

  let hglrc = wglCreateContext(hdc)
  if hglrc == 0:
    raise newException(WindyError, "Error creating rendering context")

  makeContextCurrent(hdc, hglrc)

  wglCreateContextAttribsARB =
    cast[wglCreateContextAttribsARB](
      wglGetProcAddress("wglCreateContextAttribsARB")
    )
  wglChoosePixelFormatARB =
    cast[wglChoosePixelFormatARB](
      wglGetProcAddress("wglChoosePixelFormatARB")
    )
  wglSwapIntervalEXT =
    cast[wglSwapIntervalEXT](
      wglGetProcAddress("wglSwapIntervalEXT")
    )

  discard wglMakeCurrent(hdc, 0)
  discard wglDeleteContext(hglrc)
  discard ReleaseDC(hWnd, hdc)
  discard DestroyWindow(hWnd)

proc wndProc(
  hWnd: HWND,
  uMsg: UINT,
  wParam: WPARAM,
  lParam: LPARAM
): LRESULT {.stdcall.} =
  DefWindowProcW(hWnd, uMsg, wParam, lParam)

proc platformInit*() =
  if initialized:
    raise newException(WindyError, "Windy is already initialized")
  loadOpenGL()
  registerWindowClass(windowClassName, wndProc)
  initialized = true

proc platformPollEvents*() =
  var msg: MSG
  while PeekMessageW(msg.addr, 0, 0, 0, PM_REMOVE) > 0:
    if msg.message == WM_QUIT:
      for window in windows:
        discard wndProc(window.hwnd, WM_CLOSE, 0, 0)
      # app.quitRequested = true
    else:
      discard TranslateMessage(msg.addr)
      discard DispatchMessageW(msg.addr)

proc destroy(window: PlatformWindow) =
  if window.hglrc != 0:
    discard wglMakeCurrent(window.hdc, 0)
    discard wglDeleteContext(window.hglrc)
    window.hglrc = 0
  if window.hdc != 0:
    discard ReleaseDC(window.hWnd, window.hdc)
    window.hdc = 0
  if window.hWnd != 0:
    discard DestroyWindow(window.hWnd)
    window.hWnd = 0

proc show*(window: PlatformWindow) =
  discard ShowWindow(window.hWnd, SW_SHOW)

proc hide*(window: PlatformWindow) =
  discard ShowWindow(window.hWnd, SW_HIDE)

proc makeContextCurrent*(window: PlatformWindow) =
  makeContextCurrent(window.hdc, window.hglrc)

proc swapBuffers*(window: PlatformWindow) =
  if SwapBuffers(window.hdc) == 0:
    raise newException(WindyError, "Error swapping buffers")

proc newPlatformWindow*(
  title: string,
  w: int,
  h: int,
  fullscreen: bool,
  vsync: bool,
  openglMajorVersion: int,
  openglMinorVersion: int
): PlatformWindow =
  result = PlatformWindow()
  result.hWnd = createWindow(
    windowClassName,
    title,
    CW_USEDEFAULT,
    CW_USEDEFAULT,
    w,
    h
  )

  try:
    result.hdc = getDC(result.hWnd)

    let pixelFormatAttribs = [
      WGL_DRAW_TO_WINDOW_ARB.int32,
      1,
      WGL_SUPPORT_OPENGL_ARB,
      1,
      WGL_DOUBLE_BUFFER_ARB,
      1,
      WGL_ACCELERATION_ARB,
      WGL_FULL_ACCELERATION_ARB,
      WGL_PIXEL_TYPE_ARB,
      WGL_TYPE_RGBA_ARB,
      WGL_COLOR_BITS_ARB,
      32,
      WGL_DEPTH_BITS_ARB,
      24,
      WGL_STENCIL_BITS_ARB,
      8,
      0
    ]

    var
      pixelFormat: int32
      numFormats: UINT
    if wglChoosePixelFormatARB(
      result.hdc,
      pixelFormatAttribs[0].unsafeAddr,
      nil,
      1,
      pixelFormat.addr,
      numFormats.addr
    ) == 0:
      raise newException(WindyError, "Error choosing pixel format")

    if numFormats == 0:
      raise newException(WindyError, "No pixel format chosen")

    var pfd: PIXELFORMATDESCRIPTOR
    if DescribePixelFormat(
      result.hdc,
      pixelFormat,
      sizeof(PIXELFORMATDESCRIPTOR).UINT,
      pfd.addr
    ) == 0:
      raise newException(WindyError, "Error describing pixel format")

    if SetPixelFormat(result.hdc, pixelFormat, pfd.addr) == 0:
      raise newException(WindyError, "Error setting pixel format")

    let contextAttribs = [
      WGL_CONTEXT_MAJOR_VERSION_ARB.int32,
      openglMajorVersion.int32,
      WGL_CONTEXT_MINOR_VERSION_ARB,
      openglMinorVersion.int32,
      WGL_CONTEXT_PROFILE_MASK_ARB,
      WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
      WGL_CONTEXT_FLAGS_ARB,
      WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
      0
    ]

    result.hglrc = wglCreateContextAttribsARB(
      result.hdc,
      0,
      contextAttribs[0].unsafeAddr
    )
    if result.hglrc == 0:
      raise newException(WindyError, "Error creating OpenGL context")

    # The first call to ShowWindow may ignore the parameter so do an initial
    # call to clear that behavior.
    result.hide()

    result.makeContextCurrent()

    if wglSwapIntervalEXT(if vsync: 1 else : 0) == 0:
      raise newException(WindyError, "Error setting swap interval")

    windows.add(result)
  except WindyError as e:
    result.destroy()
    raise e
