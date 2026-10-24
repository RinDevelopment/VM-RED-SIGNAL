# lua-shroud

Protection for **your own** Lua code. Two independent pipelines, both verified end to end.

## quick start

```bash
cd lua-shroud

# VM mode: source -> stripped bytecode -> remapped opcodes -> encrypted blob -> custom VM
lua cli/obfuscate.lua input.lua --key='long-random-key' --mode=vm --out=out/protected.lua --verify
lua out/protected.lua

# source mode: string pool encryption + chunked encrypted source
lua cli/obfuscate.lua input.lua --key='long-random-key' --mode=source --out=out/protected.lua --verify
lua out/protected.lua
```

`--verify` runs the original and the protected build, compares stdout and exit code, and fails the build on any difference.

## external key

Embedded mode is self-contained. External mode keeps the key out of the shipped file:

```bash
lua cli/obfuscate.lua input.lua --key="$KEY" --mode=vm --keymode=external --out=out/protected.lua
SHROUD_KEY="$KEY" lua out/protected.lua
```

No key or a wrong key: the loader exits silently.

## modes

### `--mode=vm`

1. `luac -s` compiles the source (debug info stripped).
2. Parser reads the Lua 5.1 binary chunk (endianness and word sizes handled).
3. Every opcode is remapped through a fresh per-build permutation.
4. Proto tree is serialized into a private binary format.
5. The whole blob is encrypted (rolling XOR -> RC4) and embedded.
6. A self-contained interpreter runs the instructions. No source text exists at runtime, no `loadstring` is used.

Constants (strings, numbers, booleans) travel inside the encrypted blob. No plaintext string pool in the output.

### `--mode=source`

1. Every string literal (short and long bracket) is moved into a length-prefixed pool.
2. Source is split into random chunks, each encrypted with a per-chunk key.
3. Chunk order is shuffled; every chunk carries an Adler-32 integrity value.
4. Loader reassembles, checks, and loads. Decoy blobs are embedded.

## layers

| layer | source | vm |
|---|---|---|
| string literals encrypted | yes | yes (inside blob) |
| chunked + shuffled | yes | single encrypted blob |
| per-chunk keys | yes | per-build salt |
| integrity check | Adler-32 | magic + key check |
| opcode remap | n/a | per-build permutation |
| debug info stripped | n/a | yes (`luac -s`) |
| polymorphic loader names | yes | yes |
| external key | yes | yes |
| anti-hook check | yes | yes |
| decoys | yes | n/a |

## layout

```
lua-shroud/
├── cli/obfuscate.lua        entry point
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
├── util/utils.lua
├── samples/                 verification targets
└── test/run.sh              full suite
```

## run the suite

```bash
bash test/run.sh
```

Covers both modes, external keys, script arguments, shebang handling, closures, upvalues, varargs, multret, generic/numeric loops, metamethods, >50-element constructors, and a 317 KB source.

## limits

- `--mode=vm` requires a **Lua 5.1** `luac` on `PATH`; the bytecode parser rejects other versions with a clear error. The generated interpreter itself runs on Lua 5.1+.
- `--mode=vm` compiles Lua 5.1 syntax only.
- The VM is an interpreter. Tight numeric loops run slower than native Lua; ordinary scripts are dominated by startup decrypt.
- Source mode is portable across Lua versions (uses `loadstring`/`load`).

## on "nobody can deobfuscate"

No obfuscator is absolute. If an attacker can run and instrument the process, plaintext constants eventually exist in memory. What this stack removes is the easy path: no readable source at rest, no standard bytecode signature, no stable loader fingerprint, and with `--keymode=external`, no key in the file. That is a materially higher cost than source encryption alone. Keep the key out of the artifact and rotate it per release.
