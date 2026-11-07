(() => {
  newGame({ seed: 4242, country: 'DE', name: 'Pack Test ü€😀' });
  const t = serialize();
  const small = JSON.stringify({ a: 1, s: 'héllo wörld ✓ 😀 ' + 'x'.repeat(300), n: [1.5, -2, 3e9] });
  return JSON.stringify({ t, lz1: 'LZ1:' + packText(t), lz64: 'LZ64:' + packText64(t), small, smallLz1: 'LZ1:' + packText(small), smallLz64: 'LZ64:' + packText64(small) });
})()
