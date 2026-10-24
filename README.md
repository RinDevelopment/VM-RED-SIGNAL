<div align="center">

# lua-shroud

**Source in. Nothing readable out.**

![Lua 5.1](https://img.shields.io/badge/lua-5.1-blue)
![zero deps](https://img.shields.io/badge/dependencies-zero-success)
![keyless](https://img.shields.io/badge/keyless-by%20default-informational)
![tests](https://img.shields.io/badge/tests-23%2F23%20passing-brightgreen)

lua-shroud turns your own Lua source into a self-contained artifact with no readable source at rest, no standard Lua bytecode, and no raw key. Two pipelines: a custom bytecode VM for strength, a portable source wrapper for compatibility.

*Built for code you own. Keep the source, ship the shroud.*

</div>

---

## Contents

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [What a probe finds](#what-a-probe-finds)
- [Pipelines](#pipelines)
- [Keyless by default](#keyless-by-default)
- [CLI](#cli)
- [Build output](#build-output)
- [Examples](#examples)
- [Layers](#layers)
- [Security model](#security-model)
- [Performance](#performance)
- [Tests](#tests)
- [Layout](#layout)
- [Design notes](#design-notes)
- [FAQ](#faq)
- [Status](#status)

---

## Quick start

```bash
git clone https://github.com/RinDevelopment/VM-RED-SIGNAL.git
cd VM-RED-SIGNAL

# default: vm, keyless, verified
lua cli/obfuscate.lua app.lua --out=out/app.lua --verify
lua out/app.lua
```

No key. No config. `--verify` runs the original and the protected build, compares stdout and exit code, and fails the build on any difference.

## Requirements

| Need | Why |
|---|---|
| Lua 5.1+ | run the generated loader |
| Lua 5.1 `luac` | vm builds only |
| Nothing else | no Lua modules, no build system |

---

## What a probe finds

| Probe | Result |
|---|---|
| `grep` for source strings | nothing readable |
| standard Lua bytecode in the artifact | none; the payload is a private container |
| `strings out/app.lua` | loader names and generic messages; no source, no raw key |
| `loadstring` hook | vm mode never calls it |
| debug hook set before load | loader exits |
| build A vs build B | different key, salt, opcode map, loader names |

Standard `luac` output is a documented format — `luac -l` hands the logic back. lua-shroud's vm pipeline parses the chunk, remaps every opcode through a per-build permutation, repacks it into a private container, and encrypts the result. There is no standard chunk left to disassemble.

---

## Pipelines

### `vm` — default, strongest

```text
app.lua
  │
  ├─ luac -s ────────────── strip debug info
  ├─ Lua 5.1 chunk parser ─ read protos, constants, upvalues
  ├─ opcode permutation ─── fresh map per build
  ├─ private container ──── custom proto format
  ├─ rolling XOR → RC4 ──── encrypted blob
  └─ loader + interpreter ─ one self-contained file
```

No source text exists at runtime. No `loadstring`. Constants travel inside the encrypted blob, and the interpreter maps the per-build opcode table before execution.

### `source` — portable fallback

```text
app.lua
  │
  ├─ string pool ────────── literals extracted + encrypted
  ├─ chunk split ────────── random sizes
  ├─ per-chunk encrypt ──── shuffled order
  ├─ Adler-32 ───────────── integrity per chunk
  └─ loader ─────────────── loadstring/load
```

Runs across Lua versions. Weaker than `vm`: the source is reconstructed in memory before `loadstring` sees it.

---

## Keyless by default

A fresh 64-byte key is derived from 32 bytes of OS entropy on every build. It is never printed and never stored as raw bytes.

```text
build time
  key ──► 4 XOR shares ──► permutation ──► per-byte shift + mask ──► tables

runtime
  tables ──► unshift ──► unpermute ──► XOR ──► key ──► decrypt blob
```

- No `--key` required. No `SHROUD_KEY` required.
- Share tables are set to `nil` immediately after reconstruction.
- `--key=<string>` is optional for reproducible builds. An RC4-based KDF expands it to 64 bytes, then it takes the same split-share path — the supplied string never appears in the artifact.
- `--keymode=external` keeps even the shares out of the artifact; the runtime reads `SHROUD_KEY`.

| Key mode | Build input | Runtime input | Key in artifact |
|---|---|---|---|
| `embedded` (default) | none | none | split shares only |
| `embedded` + `--key` | passphrase | none | split shares only |
| `external` | passphrase | `SHROUD_KEY` | no |

---

## CLI

| Flag | Default | What it does |
|---|---|---|
| `input.lua` | required | source file |
| `--out=<path>` | `<input>.shroud.lua` | output path |
| `--mode=vm\|source` | `vm` | pipeline |
| `--level=paranoid\|normal` | `paranoid` | source-mode chunk size, decoys, noise |
| `--keymode=embedded\|external` | `embedded` | where the key material lives |
| `--key=<string>` | generated | optional reproducible key |
| `--verify` | off | run original + protected, compare stdout and exit code |
| `--help` | — | usage |
| `--quiet` | off | no stdout; errors still go to stderr |
| `--no-color` | auto | disable ANSI colors |
| `--version` | — | print version |

Builds print a staged log with per-step timings. Colors auto-detect a TTY; `NO_COLOR` and `--no-color` disable them. `--quiet` leaves stdout clean.

---

## Build output

```text
lua-shroud  ·  vm pipeline
source in. nothing readable out.
input       app.lua  ·  784 B
key         generated  ·  64 B  ·  embedded, not shown
output      out/app.lua
[1/7] compile    ... ok  889 B  ·  0.00s
[2/7] parse      ... ok  Lua 5.1 chunk  ·  0.00s
[3/7] remap      ... ok  762 B custom  ·  0.00s
[4/7] encrypt    ... ok  XOR + RC4  ·  0.00s
[5/7] render     ... ok  18.3 KB artifact  ·  0.05s
[6/7] check      ... ok  syntax ok  ·  0.00s
[7/7] verify     ... ok  stdout + exit match  ·  0.00s
──────────────────────────────────────────────
built  out/app.lua  ·  18.3 KB  ·  0.05s
```

---

## Examples

```bash
# keyless vm, the default
lua cli/obfuscate.lua app.lua --out=out/app.lua

# portable source mode
lua cli/obfuscate.lua app.lua --mode=source --out=out/app.src.lua

# reproducible embedded key
lua cli/obfuscate.lua app.lua --key="$KEY" --out=out/app.lua

# external key: nothing key-shaped ships
lua cli/obfuscate.lua app.lua --mode=vm --keymode=external --key="$KEY" --out=out/app.lua
SHROUD_KEY="$KEY" lua out/app.lua

# build + behavior check in one shot
lua cli/obfuscate.lua app.lua --verify --out=out/app.lua
```

Script arguments and shebangs survive both pipelines.

---

## Layers

| Layer | source | vm |
|---|---|---|
| string literals encrypted | yes | yes, inside the blob |
| chunked + shuffled | yes | single encrypted blob |
| per-chunk keys | yes | per-build salt |
| integrity check | Adler-32 | magic + key check |
| opcode remap | n/a | per-build permutation |
| debug info stripped | n/a | yes, `luac -s` |
| polymorphic loader names | yes | yes |
| embedded key shares | yes | yes |
| external key (optional) | yes | yes |
| anti-hook checks | yes | yes, before decrypt and inside `dec` |
| decoys | yes | n/a |

---

## Security model

### What it stops

- Static source extraction with `grep`, `strings`, or an editor.
- Standard Lua bytecode tooling — there is no standard chunk to load.
- Raw key extraction — no key bytes are stored.
- Naive `loadstring` dumping in vm mode — it is never called.
- A debug hook set before the loader runs — the loader exits.

### What it does not stop

- A debugger attached to a running process.
- A memory dump after decryption.
- An attacker who can modify the loader itself.
- Behavior and I/O analysis.
- Unlimited time plus custom tooling.

> No obfuscator is absolute. This stack raises the cost; it does not prove impossibility. `vm` mode is the strong path, `source` mode is the compatibility path.

---

## Performance

Measured in this container, Lua 5.1.5, 317 KB input:

| Build | Output | Build time | Run time |
|---|---|---|---|
| vm | 411 KB | 1.06 s | 0.24 s |
| source | 666 KB | 1.70 s | 0.35 s |

`vm` output is interpreted; tight numeric loops are slower than native Lua. Ordinary scripts are dominated by startup decrypt. `source` mode runs at native speed after `loadstring`.

---

## Tests

```bash
bash test/run.sh
# total: 23 pass, 0 fail
```

Covers both pipelines, keyless embedded builds, external keys, per-build randomness, raw-key leak checks, CLI quiet/color/version checks, script arguments, shebang handling, closures, upvalues, varargs, multret, generic and numeric loops, metamethods, >50-element constructors, and a 317 KB source.

---

## Layout

```text
.
├── cli/
│   └── obfuscate.lua        entry point
├── core/
│   ├── crypt.lua            XOR/RC4, pack/unpack, pool serialization
│   ├── bytecode.lua         luac 5.1 binary chunk parser
│   └── vmserialize.lua      opcode permutation + private blob format
├── transform/
│   ├── tokenizer.lua        string span scanner (comments/long brackets aware)
│   ├── strings.lua          literal extraction, unescape, pool build
│   └── junk.lua             syntax-safe noise
├── loader/
│   ├── template.lua         source-mode runtime
│   └── vm_template.lua      bytecode interpreter runtime
├── util/
│   ├── report.lua           terminal presentation: banner, stages, summary
│   └── utils.lua            I/O, entropy, hashing, polymorphic names
├── samples/                 verification targets
└── test/
    └── run.sh               full suite
```

---

## Design notes

**Per-build randomness.** Key, salt, opcode permutation, chunk order, and loader names change on every build. There is no stable signature to match.

**Private container.** The vm payload is not a Lua chunk. `luac -l` has nothing to read, and the interpreter maps a per-build opcode table before execution.

**Split key shares.** A self-contained artifact normally needs a key somewhere. Here the key exists only as four permuted XOR shares with per-byte shifts and masks; the loader reconstructs it, decrypts, and drops the tables.

**Anti-hook checks.** The loader refuses to run when `debug.gethook` reports an active hook, and checks again inside `dec` before producing plaintext.

**Two modes, one tradeoff.** vm for protection, source for portability. Use vm unless the target runtime cannot supply Lua 5.1 bytecode compatibility.

---

## FAQ

<details>
<summary><strong>Does it need a key?</strong></summary><br>

No. Embedded mode generates one per build and hides it in the artifact.
</details>

<details>
<summary><strong>Can I use my own key?</strong></summary><br>

Yes. `--key=<string>` is optional and useful for reproducible builds. It is expanded to 64 bytes and embedded through the same split-share path.
</details>

<details>
<summary><strong>Can it be deobfuscated?</strong></summary><br>

Not absolutely. A debugger attached to a running process can eventually observe plaintext. The goal is to remove the cheap paths: source at rest, standard bytecode, raw keys, and naive hook dumps.
</details>

<details>
<summary><strong>Can I ship one file?</strong></summary><br>

Yes. Embedded mode is self-contained. External mode needs `SHROUD_KEY` at runtime.
</details>

<details>
<summary><strong>Why is vm slower?</strong></summary><br>

It is an interpreter. Startup decrypt plus per-instruction dispatch costs more than native Lua, especially in tight numeric loops.
</details>

<details>
<summary><strong>Does source mode hide strings?</strong></summary><br>

Yes, literals move into an encrypted pool, but the source is reassembled in memory before `loadstring`. vm mode is stronger.
</details>

<details>
<summary><strong>What Lua versions are supported?</strong></summary><br>

Builds target Lua 5.1. vm mode additionally requires a Lua 5.1 `luac` on `PATH`. Generated vm output is Lua 5.1-compatible. Source mode uses `loadstring`/`load` and runs across Lua versions.
</details>

---

## Status

| | |
|---|---|
| Tests | `23/23` passing |
| Default mode | `vm` |
| Default key mode | `embedded` |
| Runtime dependencies | none |

---

<div align="center">

*lua-shroud — keep the source, ship the shroud.*

</div>
