# Changelog

## 1.0.2

- Fixed: making a route with the same name as one already in that zone made a hidden copy that sat under the first one on the map. Now each route in a zone needs its own name: GatherPath says so in chat and keeps what you picked, so you can change the name (or Rebuild the route you already have). Renaming a route to another route's name in the same zone is turned down the same way.

## 1.0.1

- The description now recommends GatherMate2 Data (Wowhead Classic): import its herb and ore nodes into GatherMate2 to make full routes through a zone before you've gathered it yourself.

## 1.0.0

- First release.
- Make routes from GatherMate2's herb, ore, fishing and treasure nodes: pick a zone and the nodes, and GatherPath finds the shortest loop through them.
- Routes are drawn on the world map (the zone's map, and thinner on the continent's) and on the minimap, turning with it.
- Several routes per zone, each with its own color; show, hide, rename, rebuild or delete each one.
- Nodes GatherMate2 records later join the routes they belong to.
- Merge nodes closer than a distance you choose into one stop.
- Line widths, opacity, a minimap button, and `/gpf`.
