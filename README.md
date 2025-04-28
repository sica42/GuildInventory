# GuildInventory
**Version:** 0.1  
**Game Version:** Turtle WoW (Interface 11200)

GuildInventory is a shared inventory for guilds. Members can add items that they want to make available to other members.
For now you'll have to manually message/mail members to request items.

Still BETA!
If you see a green/yellow dot continuously blinking in the top right corner do a `/reload`!!

---

## ✨ Usage

Drag & drop items from your inventory or bank to add items. If you put an item in the last slot the inventory will expand.
The ordering of items is local to you only, so you can use drag & drop to order them however you want. Note that any items being added during a sync will be added to the first avaiable slots.

Clicking an item will show you who has the item avaiable. You can also manually update your own count after clicking an item.
Setting your count to 0 will remove the item if no other members has added any.

The `sync inventory` and `sync bank` buttons will updated the count of any items you've added with the total from your inventory/bank.
Note that you have to either add items from your inventory or update the count manually on items first for the sync to work.

You can assign a hotkey in Key Bindings to toggle the window.

---

## 🧰 Slash Commands

Type `/gi` or `/guildinventory` in chat to see all options.
- `/gi show` - Open guild inventory.
- `/gi close` - Close guild inventory.
- `/gi toggle` - Toggle gulid inventory.

Commands avaiable while in BETA:
- `/gi clear` - Clears your local guild inventory.
- `/gi refresh` - Updated inventory from other members.
- `/gi broadcast` - Broadcast your version of the inventory to other members.  

---

## 📦 Installation

Using the Turtle Wow Launcher:

Copy and paste https://github.com/sica42/GuildInventory into the launcher.

Manual install:
1. Download or clone the addon into your `Interface\AddOns\` folder.
2. Make sure the folder is named `GuildInventory`.
3. Restart WoW.

---

## 📄 License

MIT License — do what you want with it. Credits appreciated but not required.