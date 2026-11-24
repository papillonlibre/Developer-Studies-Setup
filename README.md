# Developer Studies Setup

Builds a pinned, tested GPU VM for developer-experience studies of NeMo Helix 0.6 on
[Brev](https://brev.nvidia.com). The goal is a clean machine: everything that is not being studied
is installed, pinned and smoke-tested, so friction comes from the product and its docs.

Target hardware: 1x L40S (48 GB). The model is Nemotron 3.5 Bolt, served locally with llama.cpp.

## Use it

In the Brev launchable, paste the contents of [`bootstrap.sh`](bootstrap.sh) as the setup script.
It fetches this repository at a pinned version and runs `scripts/setup.sh`.

To try it by hand on an existing instance, as the login user (not root):

```bash
curl -fsSL https://raw.githubusercontent.com/papillonlibre/Developer-Studies-Setup/main/bootstrap.sh | bash
tail -f /tmp/spindrift-setup.log        # progress; ends with "smoke test PASSED"
```

The VM is ready when `/var/run/spindrift-ready` exists. To re-check later: `~/study/smoke-test.sh`.

## Layout

```
bootstrap.sh              the only thing pasted into Brev: fetch this repo, run setup
configs/
  versions.env            every pinned version, digest and commit
  study.env               names, ports and the agent identity
  *.tmpl                  config files filled in at setup time (Hermes, Relay, smoke test, service)
scripts/
  setup.sh                runs the steps below in order
  steps/01_..09_*.sh      one file per setup stage, each short enough to read in a minute
  lib/common.sh           shared settings and helpers
  smoke_test.sh           the checks that decide "ready"
  replay_traces.py        loads the example traces into Helix Intake once it is running
  sanitize_traces.py      makes the example traces describe a single agent
```

## Changing things

- A version or pin: edit `configs/versions.env`, and say why in the commit message.
- A name, port or the agent identity: edit `configs/study.env`.
- A config file the VM writes: edit its `.tmpl` in `configs/`. If it uses a new variable,
  add that variable to `RENDER_VARS` in `scripts/lib/common.sh`.
- Before a study, pin `REPO_REF` in `bootstrap.sh` to a full commit SHA so every VM is identical.

Any shell script can be syntax-checked with `bash -n <file>`.
