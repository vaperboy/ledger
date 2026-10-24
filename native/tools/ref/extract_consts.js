// Pull object/array literals out of the ORIGINAL source by name and write them as JSON (for data files).
// usage: node extract_consts.js <source.js> <NAME[,NAME...]>
const fs = require('fs');
const [, , file, names] = process.argv;
const src = fs.readFileSync(file, 'utf8');
const out = {};
for (const name of names.split(',')) {
  const m = new RegExp('\\bconst ' + name + ' = ').exec(src);
  if (!m) { out[name] = null; continue; }
  let i = m.index + m[0].length, depth = 0, start = i, inStr = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (inStr) { if (c === '\\') i++; else if (c === inStr) inStr = null; continue; }
    if (c === '"' || c === "'" || c === '`') { inStr = c; continue; }
    if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') { depth--; if (depth === 0) { i++; break; } }
  }
  out[name] = (0, eval)('(' + src.slice(start, i) + ')');
}
console.log(JSON.stringify(out));
