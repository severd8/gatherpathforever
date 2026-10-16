<p align="center"><img src="https://raw.githubusercontent.com/severd8/gatherpathforever/main/art/logo.png" width="160" alt="GatherPath Forever logo"></p>

# GatherPath Forever

**Gathering routes for World of Warcraft: Forever.**

GatherPath Forever takes the herb and ore nodes GatherMate2 has recorded, works out the shortest loop through them, and draws it on your world map and minimap. Pick Peacebloom and Silverleaf in Elwynn Forest, or every vein in a zone, and follow the line.

Needs **GatherMate2** (on CurseForge), which records where you find nodes.

---

## Features

- **Routes from your GatherMate2 nodes.** Pick a zone and the kinds of node you gather (herbs, ore, fishing pools, treasure), and GatherPath finds the shortest loop through all of them.
- **On the world map**, on the zone's map and thinner on the continent's, and **on the minimap**, round you, turning with it if your minimap turns.
- **As many routes as you like**, several per zone, each with its own color. Show or hide each one, rename it, or delete it.
- **Routes that grow.** When GatherMate2 records a node you just found, it joins the routes in that zone that have its kind, where it adds the least walking. **Rebuild** reads every node again and finds the loop again.
- **Merge nearby nodes** into one stop if you like, so the route has fewer turns.
- **Your look**: line width on the world map and on the minimap, and opacity.
- The same look as TauntMaster Forever, ToppedOff Forever, Outfitter Forever and BattleText Forever.

## Installation

1. Download the latest release.
2. Unzip it into your WoW: Forever `Interface\AddOns` folder so you end up with an `AddOns\GatherPathForever\` folder.
3. Install **GatherMate2** too.
4. Restart the game, or type `/reload` if it's already running.

## Using it

1. **Open GatherPath**: type `/gpf`, or left-click the minimap button.
2. **New route**: pick the zone (it starts on yours) and switch on the nodes you want. The number beside each is how many GatherMate2 knows there.
3. Leave the name blank to have one made from what you picked, or type your own. Click **Make route**.
4. The route shows on the **Routes** tab and on your maps. Follow the line.

- **Rebuild** a route after gathering more of a zone, so it takes in every node GatherMate2 knows now.
- **Hide every line for a while**: right-click the minimap button, or type `/gpf hide` (and `/gpf show`).

### Window

| Tab | What's there |
|---|---|
| **Routes** | The routes in a zone: color, name (click to rename), nodes, length in yards, show, Rebuild, Delete |
| **New route** | Zone, the nodes GatherMate2 knows there, name, merge nodes closer than, Make route |
| **Display** | Lines on the world map and the minimap, their widths, opacity, add new nodes to routes, minimap button |

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

Found a bug or have an idea? [Open an issue](https://github.com/severd8/gatherpathforever/issues/new/choose).

## Support

GatherPath Forever is free and always will be. If it saves you time, you can leave a tip on [Ko-fi](https://ko-fi.com/tauntmasterforever).

## License

MIT. See [LICENSE](LICENSE).
