(() => {
  // The kind of every piece of equipment (machine, tool, IT, software ...) for the breakdown model.
  const kinds = {};
  for (const id of BD_ORDER) {
    const bd = BD[id]; kinds[id] = {};
    bd.eq.forEach(e => { if (!e.vo) kinds[id][e.id] = R6.kindOf(bd, e); });
  }
  const vclassOf = {};
  Object.keys(VEH).forEach(m => { const c = VEH[m][2]; vclassOf[m] = m === 'van_box' || m === 'foodtruck' ? 'boxvan' : m === 'excav' ? 'plant' : m === 'crane' ? 'crane' : ({ car: 'car', van: 'van', truck: 'truck', bus: 'bus', bike: /scooter/.test(m) ? 'scooter' : 'bike', plant: 'plant', ship: 'ship', plane: 'plane' }[c] || 'car'); });
  return JSON.stringify({ kinds, vehicleClass: vclassOf });
})()
