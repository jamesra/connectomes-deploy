---
name: build-host-agent-ops
description: >-
  Working habits for agents running nornir jobs on a shared build host (srv / opr-marc-build2): long-job
  waiting, the shared nornir-build container and GPU, checking that a pipeline did its work, messaging peer
  sessions, and one-off repair scripts. Use before launching a long nornir job, installing an image, or
  messaging another session on the host.
---

# Agent habits on a shared build host

Each rule comes from a mistake that cost time on srv in November 2026.

## Long jobs
- Run the job in tmux and start `Logs/nornir-build/scripts/watch_job.sh '<your session name>' '<label>' "<done-check>" <log>`
  in a second tmux session. Done-check: `! docker exec nornir-build pgrep -f '<Vol> <Pipeline>' >/dev/null`.
  Why: a Bash `run_in_background` waiter dies at 2 h, but the job doesn't, so you lose the notice.
- A host reboot kills tmux watchers. Re-arm them after any reboot notice from Host.
- Keep each long job's exact launch command in a file next to its log (the runner script plus a one-line
  `restart.txt`). Why: restarts after a failure or an image install otherwise mean searching the transcript.
- A done-check must not count markers (`EXIT 0`) in logs appended across runs; use a process check
  (`! pgrep -f <runner>`) or a fresh log per run. Why: an old marker made the watcher report "done" at once.
- Killing a tmux runner's bash does not stop the `docker exec` batch it started. Let the batch finish and record it
  by hand, or kill the in-container PID. A lane that claims work before running must remove its claim when its
  batch is interrupted, or that work is silently skipped.

## Shared nornir-build container and GPU
- Before installing an image, list the python processes in the container (`ps -eo pid,etime,args`). The owner is in
  the run id (`agent-<Vol>-...`). Ask the owner for its batch boundary; usually one session installs for everyone.
  Why: a rebuild kills every process in the container.
- Orphaned python forkserver trees (PPID 1, 0% CPU) stay behind after finished or killed runs and make
  `install_image.sh` abort "busy" (older copies showed an empty list). Check they're idle in `top`, then `kill -9` the
  roots and their children by PID.
- Before a CuPy run, check `nvidia-smi`. If another session holds most of the GPU, use `-computational_library numpy`
  or set `-GpuWorkers`, and tell that session. Why: AssembleTiles and StosBrute both died with CuPy out-of-memory
  errors when sharing the GPU.
- The masked StosBrute (nornir ≥1.7.7) needs about 3 GB of GPU memory per ds64 pair and runs about 30x slower than
  the old scorer (about 650 s per pair on srv). Plan volume-wide brutes from that number.

## Pipeline success is not "exit 0"
- After every pipeline, check that its outputs exist: files in the output group or level folder, and new XML nodes.
  Why: a Pipelines.xml `<Select>` that matches nothing silently skips the stage. AlignSections once exited 0 in 2 min
  with no brute at all, because -OutputStosMap was ignored (fixed in 1.7.8).
- Grep the tee'd log for `Traceback|Error|OutOfMemory|Skipping`, not only the last line.

## Peer sessions
- Run `ListAgents` before messaging. Session names change after restarts (srv-0e → srv-60; "Build2 RC RC3" was
  briefly "docker-b3"). To reply, copy the incoming message's `from=` address.

## One-off repair scripts
- When you reuse an older one-off script, first restrict it explicitly to the sections or files in scope, then dry-run
  it and read the counts. Why: a reused stos image-line fixer would have rewritten other sections' files.
- After renaming or adding a filter: the stos XML `Mapped/ControlFilterName`, the stos file names and the stos image
  lines must all name it. ScaleStosGroup and CreateVikingXML silently drop a section whose stos names a missing filter.

## Viking side of a mixed volume
- Give every section the same filter name (e.g. `Quantized`) even when the sources differ, and leave the Crush*
  attributes off filters that aren't crushed. Viking falls back to a section's default channel, but the
  segmentation server picks the volume's DefaultTileset (else the first by name), and the gallery asks for the
  tileset by exact name.
