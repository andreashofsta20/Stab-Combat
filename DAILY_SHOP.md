# Daily shop and shop navigation

The daily shop uses exactly **three SmallItemTemplate clones in Daily.Others and two LargeItemTemplate clones in Daily.Main**. The five offers are shared by every player/server running the same configuration and asset catalog. Stock changes at **00:00 UTC every day**, including while the shop is open. Owned offers remain visible; ownership never rerolls someone into different stock.

Daily offers exclude Godly rarity, emotes, the Shadow Dagger starter knife, the White&Black starter revolver, and untradeable/missing weapons. Those exclusions are enforced by the catalog and purchase handler. Existing case contents and Robux/VIP purchase flows retain their current behavior, including the Emotes case category.

## Configuration

Edit `src/Modules/DailyShopConfig.luau`:

- `Items`: explicit allowlist by `Knife` / `Revolver`. Adding a weapon definition alone does not list it in the shop.
- `RarityDefaults`: default Gold price and minimum level for each weapon type/rarity.
- Each allowlist entry can specify `{Price = 2400, MinLevel = 5}` or `{Enabled = false}`.
- `Slots`: the weapon type and allowed rarities for each of the five offers. Slots 1-3 use small templates; slots 4-5 use large templates. No duplicate weapon can occupy two slots. An empty eligible pool leaves its own slot empty, preserving the other offers' positions.
- `ResetSeconds = 86400` and `ResetOffsetSeconds = 0`: daily midnight UTC. Offsets use UTC seconds; they do not follow daylight saving time.
- `Version`: increment when changing catalog, prices, slots, seed, or reset schedule, and update/restart servers together. A version change invalidates displayed older offers and begins a new purchase rotation.
- `UI`: names of optional existing buy, level, reset timer and status controls. Template, parent, position and required label references are passed explicitly from ShopGUI.

Starting prices use the existing economy (50 Gold per kill and roughly 200-700 Gold per win). They charge for a chosen item rather than a random reward. These are initial balance values, to tune with actual acquisition and spending data.

| Rarity | Knife Gold | Revolver Gold | Required level |
| --- | ---: | ---: | ---: |
| Common | 650 | 500 | 0 |
| Rare | 2,200 | 1,400 | 3 |
| Epic | 5,500 | 3,000 | 8 |
| Legendary | 15,000 | 6,500 | 15 |

For example, add `Items.Revolver["Sterling Revolver"] = {Price = 3200, MinLevel = 9}`. The name must match `RevolversInfo` and a Tool in `ServerStorage.Revolvers`. Knives need matching `KnivesInfo` and `ServerStorage.Knives` Tool entries. Godly/emote entries are rejected even if accidentally put in the allowlist.

## Existing daily templates and layout

ShopGUI reads your authored templates and fields directly. The daily controller only clones those templates; it never creates a fallback frame, card, label, layout or purchase button.

```text
Main.Frames.Shop
  Menu
    Daily (ImageButton or TextButton)
    Cases (ImageButton or TextButton)
  Holders
    Daily
      Others (three SmallItemTemplate clones)
      Main (two LargeItemTemplate clones)
      ResetTimer (TextLabel, optional)
      ShopStatus (TextLabel, optional)
    KnivesCases (ScrollingFrame)
    RevolversCases (ScrollingFrame, optional)
    Emotes (ScrollingFrame; EmotesCases also supported)
  CratesTabSelection
    Knives (ImageButton)
    Revolvers (ImageButton)
    Emotes (ImageButton)

ReplicatedStorage.UITemplates.DailyShopTemplates
  SmallItemTemplate
    AlreadyOwned
    ItemImage
    Divider
      ProductName
      Price
  LargeItemTemplate
    AlreadyOwned
    ItemImage
    Divider
      ProductName
    ItemPrice
      Text
```

The layout in ShopGUI uses these exact positions. Template Size, AnchorPoint and appearance are preserved.

| Slot | Template | Parent | Position |
| --- | --- | --- | --- |
| 1 | SmallItemTemplate | Daily.Others | `UDim2.new(0, 0, 0, 0)` |
| 2 | SmallItemTemplate | Daily.Others | `UDim2.new(0, 0, 0.5, 0)` |
| 3 | SmallItemTemplate | Daily.Others | `UDim2.new(0, 0, 1, 0)` |
| 4 | LargeItemTemplate | Daily.Main | `UDim2.new(0, 0, 0, 0)` |
| 5 | LargeItemTemplate | Daily.Main | `UDim2.new(1, 0, 0, 0)` |

`Divider.ProductName` displays `Knife - Bowie` or `Revolver - Amber Revolver`. Small costs use `Divider.Price`; large costs use `ItemPrice.Text`. `AlreadyOwned` covers owned offers and offers purchased during the current rotation. Existing price/level labels show eligibility and purchase state. Cash, XP and the five displayed inventory quantities update those cards without reopening.

Purchasing uses the template itself when it is a GuiButton, otherwise an existing Buy/BuyButton/Purchase, ItemPrice, price or ItemImage GuiButton. A template without a purchase control produces a diagnostic instead of invented UI. Optional level, rarity, reset and status labels are reused when present.

## Cases and transitions

Cases/Crates opens **all Revolver cases first** and shows `CratesTabSelection`. Selecting Knives, Revolvers or Emotes hides the other categories and tweens the selected button background to RGB **71, 81, 95**; other buttons use **46, 53, 63**. The legacy Cases frame supports category filtering when a dedicated RevolversCases frame is absent. Daily, Robux and Back hide the selector. ShopGUI initializes with only the Menu visible.

`src/PlayerClient/Modules/UITransitions.luau` owns root open/close, category colors and top-button hover animations. `ShopTransitions` remains a compatibility entry point. Settings live in `src/Modules/UIAnimationConfig.luau`:

- Open: 0.24 seconds, Quint Out, from 12 pixels below the authored position.
- Close: 0.14 seconds, Quad In, to 8 pixels below; hide and restore the authored position on completion.
- Category colors: 0.14 seconds, Quad Out.
- Top-button hover: 0.12 seconds, 1.06 times its authored dimensions, restoring the exact authored Size on leave.

Rapid toggles cancel the previous tween and stale completion callback. Reopening during close continues from the current position. The shop root uses one Position tween with no full-tree UIScale animation or CanvasGroup wrapper. This also fixes the old top-button hover target whose Y scale was 135.

## Work outside opening

The daily controller prepares one template clone per Heartbeat at startup, then keeps those five clones across responses, rotations and reopening. It caches controls, only writes changed properties and spreads offer updates across frames. Opening a fresh shop does not request stock again, clone cards, scan descendants or preload assets. Hidden settled UI performs no timer/property writes.

`ShopAssets` warms UI image IDs in background batches of at most four. Its initial tree scan visits at most twelve nodes per Heartbeat and stops once complete. It skips viewport/model contents, deduplicates image IDs and tolerates failed downloads. Case images and incoming daily item images join the same queue. Neither menu input nor animation waits for PreloadAsync.

## Remote protocol and persistence

No new remote instances are required. The existing `Remotes.ShopRemotes.PurchaseGold.PurchaseGoldRemote` carries:

```lua
remote:FireServer("REQUEST_DAILY_SHOP")
remote:FireServer("BUY_DAILY_ITEM", rotationId, offerId)
```

The same event replies with a table whose `Kind` is `DAILY_SHOP`, containing rotation ID, server reset timestamp, offers, ownership/eligibility, and purchase result. Numeric product IDs still prompt the existing Roblox Gold products. The client sends no price, rarity, level, quantity, or target player.

The server validates readiness, active profile session, payload types/lengths, rate limits, current rotation, listed item, ownership, minimum level and Cash. Purchases grant exactly one item. A non-yielding transaction charges Cash, calls the existing InventoryHandler, and records `profile.Data.DailyShop.Purchased[offerId]`. Failed grants restore the balance/quantity and remove a partially created item. A per-player guard prevents overlapping transactions, and successful purchases queue the normal profile save.

Cash, inventory and the daily marker share the existing session-locked ProfileStore record and OnSave snapshot. A player cannot buy the same offer twice in one rotation by trading it away or rejoining. The purchase-history table holds only the current rotation, so it does not grow indefinitely. A normal asynchronous ProfileStore save is not an acknowledgement of durable disk storage; an abrupt crash before persistence can roll the whole unsaved transaction back together.

There are no extra daily-shop DataStore requests, timers per player on the server, or randomized per-player rerolls. The server caches the current rotation. Client countdowns use `Workspace:GetServerTimeNow()` and refresh only while Daily and Shop are visible. Requests are locally throttled, and a lost purchase response triggers a snapshot check rather than an optimistic grant.

## First-person stability

`KnifeConfig.FirstPerson` and `RevolverConfig.Default.FirstPerson` now cap bob at normal running intensity, use **0.003 studs** of bob and **0.3 degrees** of camera sway, and blend walk/sprint animation influence down to **4%**. During movement, copied animation translation is capped at **0.012 studs** and rotation at **0.6 degrees**. `MovementFollowSpeed` blends suppression in/out smoothly. The shared motion module handles both weapons; inspect, knife charge/stab/throw, reload, recoil, native camera posture and gameplay authority keep their separate paths.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-daily-shop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-game-systems.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-case-viewport.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-client-ui-lifecycle.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-knife-viewmodel.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-revolver-presentation.ps1
```

Tests run the production catalog, server handler, purchase router, daily client, ShopGUI navigation, transition lifecycle, profile serialization and viewmodel math with Roblox stand-ins. They cover safe rotations, purchase validation/refunds, the exact five-card hierarchy/positions, Revolvers default, clone reuse, hidden UI inactivity, bounded image preloading, failed template preparation and rapid toggle cancellation.

These checks do not measure real Roblox FPS, GPU work, asset delivery or engine rendering. In Studio, compare cold and warm shop opening with the MicroProfiler, then check category switching, rapid toggles, daily ownership/level states and purchases. The source changes remove avoidable opening work; a live profiler capture is still needed to establish any remaining spike's cause.

Research references: [Roblox UI animation](https://create.roblox.com/docs/ui/animation), [MicroProfiler UI and tween guidance](https://create.roblox.com/docs/performance-optimization/microprofiler/tag-table), [UIScale](https://create.roblox.com/docs/reference/engine/classes/UIScale), [ContentProvider and yielding PreloadAsync](https://create.roblox.com/docs/reference/engine/classes/ContentProvider), [profiling a live client](https://create.roblox.com/docs/performance-optimization/microprofiler/use-microprofiler), [client/server validation and rate limits](https://create.roblox.com/docs/scripting/security/client-server-boundary), and [player-data purchasing and session locking](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing).
