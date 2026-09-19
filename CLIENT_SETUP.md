# Brisko Billing — Setup Guide

This guide takes you from a new Windows computer to taking your first bill. You do not need
any developer tools, and you never edit any files or type any commands. Everything is done
inside the Brisko Billing application.

---

## 1. Windows requirements

- Windows 10 or Windows 11, 64-bit
- An Intel i5-class processor (or better), 8 GB RAM, and at least a few GB free storage
- One free USB port for the receipt printer
- Printer: **TVS Electronics RP 3200 Lite**, 80mm thermal, connected by USB

An internet connection is recommended for cloud backup, but **is not required** to take
bills. Brisko Billing works fully offline (see sections 14–16).

---

## 2. Installation

You will receive **Brisko-Billing-Windows-x64-Release.zip** (or, if provided, a
**Brisko-Billing-Setup** installer).

**From the zip:**
1. Copy the zip onto the POS computer.
2. Right-click it and choose **Extract All...**, then pick a permanent location such as
   `C:\Brisko Billing`.
3. Open the extracted folder. Keep every file together — the application needs the
   `brisko_billing.exe` file **and** the files and `data` folder beside it.
4. (Optional) Right-click `brisko_billing.exe` → **Send to → Desktop (create shortcut)**
   so it is easy to open each day.

> If Windows shows a "Windows protected your PC" message the first time, click
> **More info → Run anyway**. This appears because the app is newly installed, not because
> anything is wrong.

**From the installer (if provided):** double-click it and follow the prompts. Brisko
Billing then appears in the Start menu.

---

## 3. First launch

Double-click **brisko_billing.exe** (or the shortcut). The application opens in its own
window titled **Brisko Billing**.

---

## 4. Login

- If your copy is set up for cloud backup, a **Sign in** screen appears. Enter the
  **email** and **password** you were given for your restaurant and click **Sign in**.
  You only do this once — the terminal remembers the session for next time.
- If your copy is local-only, there is no login screen and the app opens straight to the
  **Dashboard**.

Your sales are always saved on this computer. The cloud only keeps a backup.

---

## 5. Business settings

Go to **Settings** (left/bottom navigation) and fill in the **Business** section:

- **Business name** — printed at the top of every receipt (blank prints "Brisko Pizza").
- **Address** and **Phone** — printed under the name.
- **Receipt header / footer** — optional extra lines (for example a thank-you note).

Click **Save**. Nothing is printed until you save.

---

## 6. GSTIN

In **Settings**, enter your **GSTIN** (your 15-character GST number). It is checked for the
correct structure and then printed on every bill. Leave it blank if you are not GST
registered — no GST line is printed. Also set the **GST rate** if you charge GST. Click
**Save**.

---

## 7. Feedback URL

In **Settings**, enter your **Feedback URL** (for example your Google review link). Brisko
Billing prints a **"Scan to share your feedback" QR code** on paid receipts pointing at
this link. Leave it blank and no QR is printed. Click **Save**.

---

## 8. Printer setup

Before configuring the app, add the printer to Windows:
1. Plug the TVS RP 3200 Lite into a USB port and switch it on.
2. Open Windows **Settings → Bluetooth & devices → Printers & scanners** and confirm the
   printer appears. Note its exact name (for example `TVS RP 3200`).

Then in Brisko Billing → **Settings → Printer**:
1. Turn on **Print bills and kitchen slips**.
2. **Connection:** choose **USB**.
3. **Device name:** type the printer's Windows name **exactly** as it appears in Windows
   Printers & scanners. (If it is the only printer, you may leave this blank.)
4. **Paper:** choose **80mm**.
5. Click **Save printer**.

For a **network** printer instead: choose **Network**, enter its **IP address** and
**Port** (leave blank for the default 9100), then Save.

---

## 9. Test Print

Still in **Settings → Printer**, click **Test print**. A short test receipt should print
on the TVS printer.

- If it prints — printer setup is done.
- If it does not — the app tells you why (for example the printer name does not match a
  Windows printer, or the printer is offline). Fix that and test again. See
  troubleshooting (section 17).

---

## 10. Creating a Dine-in bill

1. Open **Billing** (New Bill).
2. Set the order type to **Dine-in**.
3. Tap menu items to add them to the cart. Where an item has options/variants, choose them.
4. Apply a **Discount** if needed, and confirm the **GST** line.
5. Choose **Payment** (Cash / UPI / Card / Other), enter the amount, and **Complete**.
6. The sale is saved, and the **kitchen slip (KOT)** and **customer receipt** print.

---

## 11. Creating a Takeaway bill

Same as Dine-in, but set the order type to **Takeaway** in step 2. Complete payment the
same way; the receipt and KOT print on completion.

---

## 12. Reprinting a receipt

Open the order (from **Orders**/history), open the bill, and choose **Reprint receipt**.
The same receipt prints again — it does not create a new sale.

---

## 13. Reprinting a KOT

From the same bill, choose **Reprint KOT** to print the kitchen slip again. This does not
create a new order.

---

## 14. Offline behavior

If the internet is down, Brisko Billing keeps working normally: you can create bills, take
payments, and print receipts and KOTs. Every sale is saved on this computer first, so
nothing is lost.

---

## 15. Internet / sync behavior

When the internet is available (and your copy is set up for cloud), Brisko Billing quietly
backs up your data in the background. The sync indicator at the top of the window shows the
current status. You never have to press anything to sync.

---

## 16. Backup / sync

- Your sales are always stored on this computer — that is the source of truth.
- When online, they are also copied to your private cloud backup, isolated to your
  restaurant only.
- If this computer is ever replaced, a new terminal signed in with the same account
  restores your data from the cloud backup.

---

## 17. Basic troubleshooting

- **Nothing prints:** In Settings → Printer, check printing is turned **on**, the
  **Device name** matches the Windows printer name exactly, and the printer is powered and
  has paper. Run **Test print**.
- **"Windows has no printer named ...":** the Device name in Settings does not match. Copy
  the exact name from Windows → Printers & scanners.
- **Receipt text wraps oddly:** confirm **Paper** is set to **80mm**.
- **App will not start:** make sure the whole extracted folder is intact — the `.exe` must
  stay together with its DLL files and the `data` folder.
- **Sync indicator shows offline:** check the internet connection. Billing still works;
  sync resumes automatically.

---

## 18. How to contact the developer

If something is not covered here, contact your Brisko Billing developer/supplier with:
- What you were doing when the problem happened
- Any on-screen message (a photo of the screen is ideal)
- Whether the printer test print works

_Developer contact: ____________________________  (fill in before handing over)_
