# How to run the System Diagnostics tool

These steps take about 5 minutes. No technical knowledge needed.

---

## What this tool does

It collects information about your PC so the person helping you can see
what's going on:

- Windows version, hardware specs, free disk space
- Recent error messages from Windows
- Network status (without your passwords)
- Installed updates and drivers
- Crash reports if any have happened

**It does not collect:**
- Your passwords
- Your documents, photos, music, or videos
- Anything you've typed
- Your browsing history

When it finishes, it makes a zip file you email back. The person helping
you reads it to figure out the problem.

---

## Step 1 - Save the file

You should have received a file called `run-diagnostics.bat`.

Save it somewhere easy to find, like your **Desktop** or **Downloads**
folder.

> If Windows shows a warning when you try to open it ("Windows
> protected your PC" or similar), do this first:
> 1. **Right-click** the `run-diagnostics.bat` file
> 2. Choose **Properties**
> 3. At the bottom, check the **Unblock** box (if you see one)
> 4. Click **OK**

---

## Step 2 - Run it

**Double-click `run-diagnostics.bat`.**

A black window will open with blue text. Read the message, then **press
any key** to start.

If Windows asks "Do you want to allow this app to make changes?", click
**Yes**.

The tool will run for **2-5 minutes**. You'll see a lot of text scroll
by - that's normal.

When it's done, the window will say "All done" and wait for you to press
a key.

---

## Step 3 - Send the zip file

When the tool finishes, **look on your Desktop**. You'll find:

- A folder named something like `PC-YOURPCNAME-Diagnostics-20260301-143022`
- A **zip file** with the same name (ends in `.zip`)

**Email the zip file** as an attachment to the person who sent you this
tool. (You only need to send the zip - not the folder.)

If the zip is too big for email, upload it to OneDrive / Google Drive /
Dropbox and send the share link instead.

---

## If something goes wrong

**The window closes immediately when I double-click it.**
Right-click the file -> Properties -> check Unblock -> OK. Then try
again.

**Windows says "This app can't run on your PC".**
You might have an old version of Windows. Tell the person who sent
this; they may need a different approach.

**It says "ERROR" in red.**
Take a screenshot of the window (press the **PrintScreen** key, then
paste into a Word document or email) and send it back.

**I can't find the zip file.**
Open File Explorer and look at `Desktop`. If it's not there, search for
`Diagnostics` using the search box in the top-right of File Explorer.

---

## What's in the zip?

If you're curious, you can right-click the zip and choose "Extract
all..." to see what's inside. Everything is plain text files (.txt and
.csv) that you can open in Notepad or Excel.
