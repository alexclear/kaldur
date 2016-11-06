import jester, asyncdispatch, htmlgen, os

var
  thr: Thread[void]

proc collectOnCPUMetrics() {.thread.} =
  while true:
    write(stderr, "On-CPU...\n")
    sleep(60000)

routes:
  get "/":
    resp h1("Hello world")

createThread(thr, collectOnCPUMetrics)
runForever()
