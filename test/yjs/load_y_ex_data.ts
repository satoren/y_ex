import * as Y from 'yjs' 
import fs from "node:fs"
import path from "node:path"



const doc = new Y.Doc()
const data = fs.readFileSync(path.join(import.meta.dirname , 'y_ex_v1data.bin'))
const uint8array = new Uint8Array(data);
Y.applyUpdate(doc, data)

const ytext = doc.getText('text')
const yarray = doc.getArray('array')
const ymap = doc.getMap('map')

console.log('key',ymap.get('key'))
console.log(`${1000}`,ymap.get(`${1000}`))
console.log(`${ Number.MAX_SAFE_INTEGER}`,ymap.get(`${ Number.MAX_SAFE_INTEGER}`))
console.log(`${ Number.MAX_SAFE_INTEGER+ 1000}`,ymap.get(`${ Number.MAX_SAFE_INTEGER+ 1000}`))
console.log(`${ Number.MIN_SAFE_INTEGER}`,ymap.get(`${ Number.MIN_SAFE_INTEGER}`))
console.log(`${ Number.MIN_SAFE_INTEGER- 1000}`,ymap.get(`${ Number.MIN_SAFE_INTEGER- 1000}`))
console.log(`${0.5}`,ymap.get(`${ 0.5}`))
