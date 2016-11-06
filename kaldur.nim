import jester, asyncdispatch, htmlgen, os, osproc

var
  thr: Thread[void]

proc collectOnCPUMetrics() {.thread.} =
  while true:
    write(stderr, "On-CPU...\n")
    let errCode = execCmd("perf record -F 99 -o perf.data -a -g -- sleep 60")
    write(stderr, "Error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)

routes:
  get "/":
    resp h1("Hello world")

createThread(thr, collectOnCPUMetrics)
runForever()
