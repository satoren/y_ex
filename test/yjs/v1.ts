import * as Y from 'yjs' 
import fs from "node:fs"
import path from "node:path"



const doc = new Y.Doc()
const ytext = doc.getText('text')
const yarray = doc.getArray('array')
const ymap = doc.getMap('map')
const xml = doc.getXmlFragment('xml')


ytext.insert(0, 'Hello World')
yarray.push(['Hello', 'World'])
ymap.set('key', 'value')


ymap.set(`${1000}`, 1000)
ymap.set(`${ Number.MAX_SAFE_INTEGER}`, Number.MAX_SAFE_INTEGER)
ymap.set(`${ Number.MAX_SAFE_INTEGER+ 1000}`,  Number.MAX_SAFE_INTEGER + 100)
ymap.set(`${ Number.MIN_SAFE_INTEGER}`, Number.MIN_SAFE_INTEGER)
ymap.set(`${ Number.MIN_SAFE_INTEGER- 1000}`, Number.MIN_SAFE_INTEGER - 100)
ymap.set(`${0.5}`, 0.5) 

const xmlElement = new Y.XmlElement('element')
const xmlElement2 = new Y.XmlElement('element')
xml.insert(0, [xmlElement,xmlElement2])

xmlElement2.setAttribute('eee', new Y.XmlElement('element'))
console.log('xmlElement2', xmlElement2.getAttribute('eee'))

const data = Y.encodeStateAsUpdate(doc)

fs.writeFileSync(path.join(import.meta.dirname , 'yjs_v1data.bin'), data, {
  encoding: 'binary'
})