# Weapon attachments

`src/server/WeaponAttachments.server.luau` is a standalone server Script under the existing Rojo mapping. It creates cosmetic `BackKnife` and `SideRevolver` models inside each character's `WeaponAttachments` folder. No extra remote or client loader is needed.

It watches `leaderstats.EquippedKnife` and `leaderstats.EquippedGun` and the actual Tools parented to the character. Holding any known knife hides the back knife; holding any known revolver hides the side revolver. Unequipping or switching categories restores the other display. Respawning rebuilds both displays, and changing a selected skin updates its display. A false `DataReady` attribute suppresses attachments until initialization completes; an absent attribute is supported for simpler test places.

## Templates in Studio

The server searches these folders in order, looking in ReplicatedStorage then ServerStorage for each folder:

| Category | Preferred folder | Fallback folder |
| --- | --- | --- |
| Knife | `KnifeAttachmentTest` | `Knives` |
| Revolver | `RevolverAttachmentTest` | `Revolvers` |

Templates should have the same names as the catalog/loadout: `Ethereal`, `Valentine Knife`, `Ethereal Revolver`, `Valentine Revolver`, etc. You can retain the exact MeshParts from your examples. Tools, Models, and Accessories also work: the attachment anchor is their BasePart named `Handle`, then a Model's PrimaryPart, then its first BasePart. Multipart copies retain their geometry and are welded together. Sizes are preserved.

Templates and the base place are not stored in this repository, so ensure those folders contain the real assets in Studio. Missing templates warn once per weapon instead of blocking startup. Disable/remove the old example attachment scripts when enabling this one, to avoid duplicate displays.

Copies have scripts, interactive objects, old joints, humanoids, and physics movers removed. Parts are massless, unanchored, and have collision, touch, and spatial queries disabled, so the cosmetics do not participate in combat raycasts. The actual equipped weapons are unchanged. See Roblox's [BasePart reference](https://create.roblox.com/docs/reference/engine/classes/BasePart) for these physics/query settings.

## Per-weapon positioning

Edit `src/Modules/KnifeRevAccesoryCframe.luau`. The four supplied examples are already entered, including both revolver position adjustments and their distinct rotations. Other weapons use the category default unless their info entry supplies `CframeBackrelativeOffset`.

Offset precedence is: per-item `Items[name].Offset`, then the catalog's `CframeBackrelativeOffset`, then `DefaultOffset`. This means the Ethereal/Valentine config includes the final rotations even though RevolversInfo currently stores only their base matrices.

Example entry inside `Knife.Items`:

```lua
["Bowie"] = {
    Offset = CFrame.new(-0.2, 0.4, 0.62)
        * CFrame.Angles(math.rad(15), math.rad(90), math.rad(-30)),
},
```

For the supplied revolver geometry, tune `revolverBase` or copy its expression into a per-item entry and change its pitch/yaw/roll. Position is in torso-local studs (+X right, +Y up, +Z back). Rotations after the base matrix are local to the weapon, exactly as in the supplied examples.

R6 uses `Torso`; R15 uses `UpperTorso`. The supplied numbers were calibrated for R6 and are used on R15 as a starting point. Add `R15Offset` to an item entry for a separately tuned R15 fit. Optional `TemplateName` lets you use a cosmetic template whose name differs from its inventory item. Do not rename inventory/catalog entries to tune placement.

Different meshes need visual tuning: offsets for weapons without a supplied example are defaults, not individually calibrated fits. Changing config while a running server has already required it requires restarting that test session.

## Studio verification

Use a server with two players to check replication as well as the local view:

1. With both weapons unequipped, verify one back knife and one side revolver per character, using the selected skins.
2. Equip the knife: only BackKnife disappears. Unequip: it returns. Repeat with the revolver.
3. Switch directly from knife to revolver and back. Confirm there are no duplicate models, and the held category is hidden.
4. Change each selected skin in inventory while unequipped, then while holding it. Confirm the newly selected skin appears on unequip.
5. Check the four supplied Ethereal/Valentine fits on R6; check a separately configured R15Offset on R15.
6. Respawn repeatedly, including while a weapon is equipped. Inspect the character for exactly one WeaponAttachments folder and at most one model per category.
7. Check a multipart Tool template with an embedded script: its display keeps all parts together, has no executable scripts/Tools, and does not block thrown knives or affect stabbing queries.
8. Set DataReady false, then true: displays disappear and return. Start with no character/leaderstats, then allow normal loading, to verify late initialization.

The Rojo build and script mapping were verified locally. Roblox physics, replication, asset geometry, and equip/respawn behavior require these Studio checks; they were not executed in this environment.
