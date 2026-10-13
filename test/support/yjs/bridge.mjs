// Runs snippets of JavaScript against the real Yjs for the y_ex test suite.
//
// The Elixir side (test/support/yjs.ex) talks to this process over stdin/stdout with
// 4-byte big-endian length-prefixed JSON frames ({:packet, 4}).
//
//   request:  {"code": "<async function body>", "args": <json>}
//   response: {"ok": <json>} | {"error": "<message>"}
//
// Bytes cross the boundary as {"$bytes": "<base64>"} in both directions, and a
// bigint comes back as {"$bigint": "<decimal>"}. `ctx` lives as long as this process,
// so a test can keep Yjs documents between calls (the Elixir side clears it per test).
import * as Y from 'yjs'
import * as syncProtocol from 'y-protocols/sync'
import * as awarenessProtocol from 'y-protocols/awareness'
import * as encoding from 'lib0/encoding'
import * as decoding from 'lib0/decoding'

// stdout carries the frames, so anything a snippet logs goes to stderr.
console.log = (...args) => console.error(...args)
console.info = console.log
console.debug = console.log

const AsyncFunction = (async () => {}).constructor

let ctx = {}

const decodeArgs = (value) => {
  if (Array.isArray(value)) return value.map(decodeArgs)
  if (value !== null && typeof value === 'object') {
    const keys = Object.keys(value)
    if (keys.length === 1 && keys[0] === '$bytes') {
      return new Uint8Array(Buffer.from(value.$bytes, 'base64'))
    }
    return Object.fromEntries(keys.map((key) => [key, decodeArgs(value[key])]))
  }
  return value
}

const encodeResult = (value) => {
  if (value === undefined) return null
  if (typeof value === 'bigint') return { $bigint: value.toString() }
  if (value instanceof Uint8Array) return { $bytes: Buffer.from(value).toString('base64') }
  if (value instanceof Map) return encodeResult(Object.fromEntries(value))
  if (value instanceof Set) return Array.from(value, encodeResult)
  if (Array.isArray(value)) return value.map(encodeResult)
  if (value !== null && typeof value === 'object') {
    if (typeof value.toJSON === 'function') return encodeResult(value.toJSON())
    return Object.fromEntries(Object.entries(value).map(([key, v]) => [key, encodeResult(v)]))
  }
  if (typeof value === 'number' && !Number.isFinite(value)) {
    throw new Error(`cannot return the non-finite number ${value}`)
  }
  return value
}

const run = async ({ code, args, reset }) => {
  if (reset) {
    ctx = {}
    return null
  }
  const fn = new AsyncFunction(
    'Y', 'syncProtocol', 'awarenessProtocol', 'encoding', 'decoding', 'args', 'ctx',
    code
  )
  return fn(Y, syncProtocol, awarenessProtocol, encoding, decoding, decodeArgs(args), ctx)
}

const send = (message) => {
  const body = Buffer.from(JSON.stringify(message), 'utf8')
  const header = Buffer.alloc(4)
  header.writeUInt32BE(body.length)
  process.stdout.write(Buffer.concat([header, body]))
}

let buffer = Buffer.alloc(0)
let queue = Promise.resolve()

process.stdin.on('data', (chunk) => {
  buffer = Buffer.concat([buffer, chunk])
  while (buffer.length >= 4) {
    const length = buffer.readUInt32BE(0)
    if (buffer.length < 4 + length) break
    const request = JSON.parse(buffer.subarray(4, 4 + length).toString('utf8'))
    buffer = buffer.subarray(4 + length)
    queue = queue.then(async () => {
      try {
        send({ ok: encodeResult(await run(request)) })
      } catch (error) {
        send({ error: String(error && error.stack ? error.stack : error) })
      }
    })
  }
})

process.stdin.on('end', () => {
  queue.then(() => process.exit(0))
})
