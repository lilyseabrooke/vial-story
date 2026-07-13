# Git + Godot Workflow for Vial Story

This doc covers four things: verifying your local setup, day-to-day Git habits inside Godot, how to playtest the latest pushed build, and what PRs/merges look like on this project.

## 1. Verify your local setup

1. Clone the repo (or pull, if you already cloned it):
   ```
   git clone <repo-url> vial-story
   cd vial-story
   git checkout main
   git pull origin main
   ```
2. Open Godot 4.x, choose **Import**, and select the `project.godot` file at the repo root (there isn't one yet — see step 3 in the run-through below).
3. In the Godot editor, open **Editor > Editor Settings > Version Control** (or the small "Version Control" menu at the top of the editor) and enable the **Git** plugin if it's not already active. Godot itself doesn't run git commands for you by default — the plugin adds a diff/stage/commit panel inside the editor, but you can also just use your terminal or a Git GUI (GitHub Desktop, Fork, SourceTree, VS Code) alongside Godot. Either is fine; use whichever feels more comfortable while you're learning.
4. Run a **smoke test** before building anything real:
   - In Godot, create a throwaway scene (e.g., `res://test/hello.tscn` with a single `Label` node saying "hello").
   - Save it. Godot will generate a `.godot/` cache folder — confirm it does **not** show up in `git status` (this repo's `.gitignore` excludes it).
   - `git add`, commit, and push the new scene to a branch.
   - Delete the scene, pull again, confirm it reappears. If that round-trips cleanly, your setup is correct.
   - Delete the `test/` folder afterwards — it was just a check.

## 2. Everyday Git habits with Godot

Godot projects are mostly **text-based** (`.tscn` scenes, `.tres` resources, `.gd`/`.cs` scripts are all plain text), so Git diffs and merges them reasonably well — much better than, say, Unity's binary scene format. A few habits that keep it that way:

- **Never commit `.godot/`** — it's a regenerated cache (import data, editor state). Already excluded via `.gitignore`.
- **Be careful with `.import/`** (Godot 3) — also ignored here; Godot 4 replaced most of this with `.godot/imported/`, which is covered by ignoring `.godot/`.
- **Binary assets (art, audio, .png, .wav, etc.) don't diff or merge** — if two people edit the same texture on different branches, Git can't reconcile it; one version wins and the other is lost unless you manually redo the work. Try to avoid two people touching the same asset file at once, and consider Git LFS later if the repo grows large binary assets.
- **Scene files (`.tscn`) can conflict** just like code, especially if two people edit the same scene. Prefer splitting work into separate scenes/scripts where possible to avoid merge pain.
- **Commit often, in small logical chunks** — e.g., "add player movement script" rather than one giant "made progress" commit.

## 3. Playtesting the latest pushed version

To make sure you're playing what's actually on the remote (not stale local work):

```
git checkout main
git fetch origin
git pull origin main
```

Then in Godot:
- Open the project (Godot will pick up any new/changed scenes automatically).
- Press **F5** (or the Play button) to run the main scene, or **F6** to run the currently open scene.

If you want to test a specific feature branch or an open PR before it's merged:
```
git fetch origin
git checkout <branch-name>
```
Then reopen/re-import in Godot and play as above. Switch back with `git checkout main` when done.

## 4. Branches, PRs, and merges

Suggested flow once real work starts:

1. **Branch per feature/fix**, off `main`:
   ```
   git checkout main
   git pull origin main
   git checkout -b feature/player-movement
   ```
2. **Commit as you go**, push the branch:
   ```
   git push -u origin feature/player-movement
   ```
3. **Open a Pull Request** on GitHub from your branch into `main`. Use the PR description to note what changed and, ideally, a quick screenshot/GIF of the in-game result — much more useful for a game repo than a plain code diff.
4. **Review the diff** — for `.tscn`/`.tres` files the diff is readable text, so you can sanity-check node/property changes even without opening Godot.
5. **Merge** once satisfied (a regular merge or squash merge both work fine for a solo/small-team project — squash keeps `main`'s history to one commit per feature, which is nice for a game project with lots of small tweak commits).
6. **Pull `main` locally** after merging and delete the merged branch:
   ```
   git checkout main
   git pull origin main
   git branch -d feature/player-movement
   ```

That's the whole loop: branch → build in Godot → commit/push → PR → merge → pull `main` → playtest.
