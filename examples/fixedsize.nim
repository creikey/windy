import opengl, windy

let window = newWindow("Windy Basic", ivec2(500, 500))
window.style = Decorated

window.makeContextCurrent()
loadExtensions()

proc display() =
  glClear(GL_COLOR_BUFFER_BIT)
  # Your OpenGL display code here
  window.swapBuffers()

while not window.closeRequested:
  display()
  pollEvents()
