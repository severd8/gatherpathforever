# Changelog

## 1.4.0

- **New route** on the **Routes** tab now opens New route in the zone you were looking at, so you only have to pick the nodes. Everything else still starts blank. The **New route** tab on the left still starts with no zone.

## 1.3.0

- **Combine nodes within** is gone: **Route passes within** now does its job. Nodes close together become one stop on their own, and the route still comes within your distance of every node.
- Routes with **Route passes within** on are much shorter: about a third shorter at the default 100 yards, whether nodes grow in patches or are spread out. They are also worked out several times faster.
- Routes you already made keep their line until you **Rebuild** or **Edit** them. Do that to get the shorter route.

## 1.2.1

- Fixed: with a route already made, the window stopped filling in. On **New route** the **Zone** list was empty and the two sliders showed no values; on **Routes** the **Rebuild** button didn't grey out. Everything works again with routes in the list.
- The **Routes** tab is tidier: **Edit**, **Rebuild** and **Delete** sit in a row beside the name (they no longer overlap), and the route's details get two lines under it, so nothing is cut off.
- Clearer names on **New route**: **Merge nodes closer than** is now **Combine nodes within**, and **Pass within** is now **Route passes within**. They work the same as before.

## 1.2.0

- **New route** now opens blank every time: no zone, no nodes picked, no name, and **Merge** and **Pass within** at their defaults (off and 100 yards). Pick a zone from the list or click **My zone**.
- New **Edit** button on each route in the **Routes** tab: it opens the route's zone, nodes, name, merge and pass within so you can change them, then **Save changes** finds the loop again. The route keeps its color and stays where it is in the list. **Cancel** leaves it as it was.
- An edited route still needs a name of its own in its zone. If the nodes you pick aren't in GatherMate2, the route is left as it was.

## 1.1.1

- **Pass within** now starts at 100 yards instead of 50. Find Herbs and Find Minerals show nodes anywhere on the minimap (about 67 to 233 yards depending on zoom), so 100 still lets you see every node at any zoom and makes routes shorter. If you had it at 50 from 1.1.0, it moves to 100; set it back on the New route tab if you prefer. Routes you already made are unchanged.

## 1.1.0

- New **Pass within** setting for new routes (50 yards to start, 0 to 150): with Find Herbs or Find Minerals on you can see a node on the minimap before you reach it, so the route only comes that close to each node instead of right up to it. It cuts corners and is shorter.
- Routes list how many nodes they take you past, and how close they pass.
- Existing routes are unchanged.

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
