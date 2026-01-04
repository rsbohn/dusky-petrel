# Web Device (HTTP/HTTPS)

The web device fetches HTTP/HTTPS resources and exposes the response body in
128-word blocks. The guest writes the URL to a FIFO, sets METHOD/MODE, and
issues REFRESH to fetch the resource.

## Device code

Suggested device code: 18 (0o22).

## Modes

- METHOD: 0 = GET, 1 = HEAD
- MODE: 0 = byte (1 byte per word, low 8 bits), 1 = UTF-16 (1 code unit per word)

## I/O registers

### DOA (write)
Append a URL byte (low 8 bits). Bytes are interpreted as UTF-8.

### DOC (write)
Control word (latched):

- bit 0: METHOD
- bit 1: MODE
- bits 2-15: reserved (0)

### DIB (read)
Status flags:

- bit 0: BUSY (fetch in progress)
- bit 1: DONE (fetch complete)
- bit 2: ERROR (error present)
- bit 3: BLOCK (current 128-word block ready)
- bit 4: EOF (no more body data)
- bit 5: HEAD (response from HEAD)

### DOB/DIC (read metadata)
Write DOB with metadata index, then read DIC. DIC auto-increments the index.

- 0: HTTP status code (e.g., 200). 0 if no response.
- 1: payload length low 16 bits
- 2: payload length high 16 bits
- 3: content-type code
- 4: error code

### DIA (read body)
Read a word from the current 128-word block. After 128 reads, BLOCK clears.
Short final blocks are padded with zeros.

### NIO
- Clear: reset state, clear URL FIFO, abort in-flight fetch
- Start: REFRESH (fetch the URL currently in FIFO)
- Pulse: advance to the next block (if more data)

## Content-type codes

- 0: unknown/other
- 1: text/plain
- 2: text/html
- 3: application/json
- 4: application/octet-stream

## Error codes

- 0: OK
- 1: BadURL
- 2: ResolveFail
- 3: ConnectFail
- 4: TlsFail
- 5: Timeout
- 6: ReadFail
- 7: UnsupportedScheme
- 8: TooLarge

## Example flow

1) Write URL bytes via DOA (UTF-8):

   https://gist.githubusercontent.com/rsbohn/1e3d0312e52aff7400b8fcae6d1986f9/raw/f6dfabe94f844ad1191f9c623c99a0096dcd7723/README.md

2) DOC: METHOD=GET, MODE=UTF-16 (for text/plain;utf-16)
3) NIO Start (REFRESH)
4) Poll DIB for DONE/BLOCK
5) Read metadata: DIC for status (200), length, content-type, error
6) Read response via DIA, 128 words at a time, until EOF
