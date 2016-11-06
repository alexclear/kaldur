import jester, asyncdispatch, htmlgen, os, osproc, times

var
  thr: Thread[void]

proc collectOnCPUMetrics() {.thread.} =
  while true:
    let currentTime = toInt(epochTime())
    write(stderr, "On-CPU... " & $currentTime & "\n")
    let errCode = execCmd("perf record -F 99 -o /var/lib/kaldur/perf" & $currentTime & ".data -a -g -- sleep 60")
    write(stderr, "Error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)

routes:
  get "/":
    resp h1("Hello world")

createThread(thr, collectOnCPUMetrics)
runForever()
