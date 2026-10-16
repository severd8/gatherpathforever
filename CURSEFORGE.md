# GatherPath Forever

**Gathering routes for World of Warcraft: Forever.**

GatherPath Forever takes the herb and ore nodes GatherMate2 has recorded, works out the shortest loop through them, and draws it on your world map and minimap. Pick Peacebloom and Silverleaf in Elwynn Forest, or every vein in a zone, and follow the line.

Needs **GatherMate2** (on CurseForge), which records where you find nodes.

Recommended: **[GatherMate2 Data (Wowhead Classic)](https://www.curseforge.com/wow/addons/gathermate2-data-wowhead-classic)**. It lets you import Wowhead's herb and ore nodes into GatherMate2, so you can make a full route through a zone before you've gathered it yourself. After installing it, open GatherMate2's options, go to **Import Data** and import the nodes you want.

---

## Features

- **Routes from your GatherMate2 nodes.** Pick a zone and the kinds of node you gather (herbs, ore, fishing pools, treasure), and GatherPath finds the shortest loop through all of them.
- **On the world map**, on the zone's map and thinner on the continent's, and **on the minimap**, round you, turning with it if your minimap turns.
- **As many routes as you like**, several per zone, each with its own color. Show or hide each one, rename it, edit it, or delete it.
- **Routes that grow.** When GatherMate2 records a node you just found, it joins the routes in that zone that have its kind, where it adds the least walking. **Rebuild** reads every node again and finds the loop again.
- **Route passes within** a distance of each node instead of right up to it (100 yards to start): with Find Herbs or Find Minerals on you see nodes on the minimap from there, so the route cuts corners and is shorter, and nodes close together become one stop.
- **Your look**: line width, opacity and color, set apart for the world map and the minimap. Lines use each route's own color, or one color you pick for every route.
- The same look as TauntMaster Forever, ToppedOff Forever, Outfitter Forever and BattleText Forever.

## Installation

Install it with the CurseForge app, or download the file and unzip it into your WoW: Forever `Interface\AddOns` folder. Install **GatherMate2** too. Then restart the game or type `/reload`.

## Using it

1. **Open GatherPath**: type `/gpf`, or left-click the minimap button.
2. **New route**: click **New route** on the **Routes** tab to start in the zone shown there, or pick the zone (or click **My zone**). Switch on the nodes you want, or click **Select all** beside a kind (herbs, ore, treasure). The number beside each is how many GatherMate2 knows there.
3. The name starts with the zone ("The Barrens - "). Type the rest, or leave it to have it made from what you picked. Click **Make route**.
4. The route shows on the **Routes** tab and on your maps. Follow the line.

- **Edit** a route to change its zone, nodes, name or pass distance; it finds the loop again when you save.
- **Rebuild** a route after gathering more of a zone, so it takes in every node GatherMate2 knows now.
- **Hide every line for a while**: right-click the minimap button, or type `/gpf hide` (and `/gpf show`).

### Window

| Tab | What's there |
|---|---|
| **Routes** | The routes in a zone: color, name (click to rename), Edit, Rebuild, Delete, nodes, length in yards, show |
| **New route** | Zone, the nodes GatherMate2 knows there (with Select all for each kind), name, route passes within, Make route. Starts blank each time; Edit fills it in from a route |
| **Display** | Lines on the world map and the minimap: width, opacity, and each route's own color or one you pick, for each map; add new nodes to routes, minimap button |

### Commands

| Command | Does |
|---|---|
| `/gpf` | Open or close the window |
| `/gpf new` | Open the New route tab |
| `/gpf hide`, `/gpf show` | Hide or show every line |

## Good to know

- A route goes where your nodes are. The more of a zone you've gathered (or imported into GatherMate2), the better the route.
- The loop is as short as GatherPath can find quickly. A big route (hundreds of nodes) takes a moment to work out; the game keeps running meanwhile.
- Lengths are in yards, round the whole loop.

## Feedback

Found a bug or have an idea? Click **Issues** at the top of this page.

## Support

GatherPath Forever is free and always will be. If it saves you time, you can leave a tip on [Ko-fi](https://ko-fi.com/tauntmasterforever).

## License

MIT
