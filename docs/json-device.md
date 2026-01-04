# JSON Parser Device (JSP)

The JSON parser device reads the last response body fetched by the WEB
device and exposes a simple query interface using JSON pointer-style paths
(`"/result/0/name"`). The device returns values as either bytes or UTF-16
code units depending on MODE.

## Device code

Suggested device code: 21 (0o25).

## Control word (DOC)

- bit 0: MODE (0 = byte output, 1 = UTF-16 output)
- bit 1: STRICT (0 = missing path yields empty result, 1 = error)
- bit 2: SOURCE (0 = use WEB response, 1 = reserved/manual buffer)

## Status word (DIB)

- bit 0: BUSY
- bit 1: DONE
- bit 2: ERROR
- bit 3: VALUE (output available)
- bit 4: EOF (output drained)

## Metadata (DOB/DIC)

Write DOB with the index, then read DIC. DIC auto-increments.

- 0: result type (0 missing, 1 string, 2 number, 3 bool, 4 null, 5 object, 6 array)
- 1: error code
- 2: value length low 16
- 3: value length high 16

## Error codes

- 0: OK
- 1: NoSource (no WEB response)
- 2: BadJson
- 3: BadPath
- 4: TypeMismatch
- 6: Internal

## Query flow

1) Write query bytes via DOA (UTF-8), null-terminate with `0`.
2) DOC to set MODE/STRICT as needed.
3) NIO Start to execute the query.
4) Poll DIB for DONE/ERROR.
5) Read DIC metadata.
6) Read output via DIA until EOF.

## Example

The `sd/rockets.asm` sample fetches JSON with WEB and prints:

- `/result/0/t0`
- `/result/0/name`
- `/result/0/launch_description`

Output is UTF-16 via UTTO so Unicode spacing (e.g., U+202F) renders correctly.
