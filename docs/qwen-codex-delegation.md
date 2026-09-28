# Qwen delegation through Codex

## Connection

Use the user's existing local Ollama configuration:

```bash
codex --oss --local-provider ollama --model qwen3.6:27b
```

For delegated tasks, use `codex exec` with the same provider and model. This launches a separate worker; it does not attach to an existing interactive Codex process. An interactive session's PID is not a connection setting. Leave that session running and do not reuse or terminate its PID.

The connection was verified on 2026-09-28 with Codex 0.157.1: a minimal prompt returned `QWEN_CONNECTION_OK`, and a separate read-only review completed. Both runs reported a model-metadata warning but exited successfully. Completion of that limited review does not establish correctness of the full dashboard.

Command reference: [official Codex CLI documentation](https://developers.openai.com/codex/cli/reference).

## Required background workflow

User requirement, recorded 2026-09-28: Qwen is slow, so run delegated tasks in the background and check their status every few minutes.

- Launch each task asynchronously. Continue independent implementation, documentation, or validation while it runs.
- Check status approximately every **3 minutes**; a **2–5 minute** interval is appropriate. Check sooner if a completion notification arrives. Do not poll every few seconds.
- Do not block the primary agent with a multi-minute sleep. Use its background process/session facility, or continue useful work until the next check. If waiting is necessary, keep each individual blocking wait at most 60 seconds while retaining the overall polling interval.
- Allow several minutes for loading, prompt processing, and reasoning. Silence or a metadata warning alone does not mean failure. Do not impose a short timeout or launch duplicate workers because output is delayed.
- Use one Qwen worker at a time by default to avoid local model contention. Give it a small, predefined task with explicit files, acceptance criteria, and expected output.
- Record the task, working directory, launch time, process/session identifier, and output paths. Preserve these details across conversation handoffs so the next agent can check the existing task.
- At each status check, inspect completion/exit status and recent output. Report whether it is running, completed, or failed; do not claim a pending review passed.
- If the worker exits with an error, inspect that error before retrying. If a long-running task appears stalled, inspect its status and the local Ollama service before deciding whether to stop or retry it. Slow execution alone is insufficient evidence.
- Read and independently verify Qwen's findings before applying changes or reporting them as confirmed. Wait for required findings before completing dependent work.

## Task scope

Follow the repository's `AGENTS.md`. Default to read-only review and supply only the source needed for the task. Never send secrets, backups, or production data. For an approved implementation task, use a separate feature worktree and explicitly scoped files so the primary agent and worker do not edit the same files concurrently. Existing commit, push, merge, and deployment approval requirements still apply.

When a tool runner provides a background session ID, save it and poll that session on the schedule above. Network sandbox restrictions may prevent access to localhost; use the normal approval mechanism if needed. Do not disable the worker's sandbox to solve a connection problem.

## Terminal example

Run this from the intended feature worktree. Keep the launching terminal open for the duration of the task. Replace the example review prompt with the agreed bounded assignment when needed.

```bash
qwen_workspace="$PWD"
qwen_task_dir=$(mktemp -d /private/tmp/navig8r-qwen.XXXXXX)

(
  if codex exec \
    --oss --local-provider ollama \
    --model qwen3.6:27b \
    --sandbox read-only --ephemeral \
    -C "$qwen_workspace" \
    -o "$qwen_task_dir/result.md" \
    'Follow AGENTS.md. Review only dashboardPermissions and the initial
     authorization and pagination checks in apps/api/src/dashboard.ts.
     External principals must be denied; each section needs its mapped
     permission; financial sections also need FINANCE; inactive records
     also need ADMIN. Limits must be integers from 1 to 100 and offsets
     must be nonnegative integers. Report concrete discrepancies with
     file references, or state no discrepancies found in this scope.
     Do not modify files, delegate further, or read secrets, backups,
     or production data. Keep the report under 200 words and state its
     limitations.' </dev/null; then
    qwen_exit_code=0
  else
    qwen_exit_code=$?
  fi
  printf '%s\n' "$qwen_exit_code" > "$qwen_task_dir/exit-code"
) > "$qwen_task_dir/run.log" 2>&1 &

printf '%s\n' "$!" > "$qwen_task_dir/worker.pid"
printf 'Qwen task directory: %s\n' "$qwen_task_dir"
```

Save the printed task directory. Shell variables may not persist between agent tool calls; use that absolute path in subsequent checks. After approximately three minutes, inspect status:

```bash
if test -f "$qwen_task_dir/exit-code"; then
  printf 'Worker exit code: '
  cat "$qwen_task_dir/exit-code"
  if test -f "$qwen_task_dir/result.md"; then
    cat "$qwen_task_dir/result.md"
  fi
else
  printf 'No completion recorded yet. Recent output:\n'
  tail -n 10 "$qwen_task_dir/run.log"
fi
```

Exit code `0` plus a completed report establishes successful task execution. Independently review the report's substance. A missing exit-code file means completion has not been recorded; if the terminal or worker disappeared, diagnose that interruption instead of assuming it is still running. Keep output files out of version control unless a reviewed project document specifically needs the findings.
