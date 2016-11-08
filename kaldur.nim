import jester, asyncdispatch, htmlgen, os, osproc, times

var
  thr: Thread[void]

proc foldStacks(timestamp: int) {.thread.} =
  write(stderr, "Folder... " & $timestamp & "\n")
  let errCode = execCmd("perf script -i /var/lib/kaldur/perf" & $timestamp & ".data | /root/FlameGraph/stackcollapse-perf.pl > /var/lib/kaldur/out" & $timestamp & ".perf-folded")
  write(stderr, "Folder finished, error code: " & $errCode & "\n")
  if errCode != 0:
    quit(QuitFailure)

proc collectOnCPUMetrics() {.thread.} =
  while true:
    var thr1: Thread[int]
    let currentTime = toInt(epochTime())
    write(stderr, "On-CPU... " & $currentTime & "\n")
    let errCode = execCmd("perf record -F 99 -o /var/lib/kaldur/perf" & $currentTime & ".data -a -g -- sleep 60")
    write(stderr, "Error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)
    write(stderr, "Creating a new thread\n")
    createThread(thr1, foldStacks, currentTime)
    write(stderr, "New thread created!\n")

routes:
  get "/":
    resp h1("Hello world")

createThread(thr, collectOnCPUMetrics)
runForever()
