# Order History Reset

The Bills / Order History screen is retained. This reset is **not automatic**.

To permanently remove existing orders from the MongoDB database and restart order numbering from #1, run the guarded maintenance utility from `backend`:

```powershell
$env:CONFIRM_FRESH_RESET="YES"
node src/utils/resetFreshDatabase.js
```

This deletes all `Order` documents and resets the `orderNumber` counter to 0.

Do this only for a fresh/test deployment or when you intentionally want to clear pre-launch data. Do not run it on a live cafe database containing real sales.
