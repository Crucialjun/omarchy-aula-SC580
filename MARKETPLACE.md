# Publishing to the Omarchy plugin marketplace

Checklist against https://plugins.omarchy.org/publish.html and the
marketplace repo's `SUBMISSION.md` (omacom/omarchy-plugin-marketplace):

- [x] One plugin, `manifest.json` at the repository root
- [x] Root `README.md` with install **and removal** instructions and external dependencies (python3, udev rule)
- [x] Root `LICENSE` (MIT)
- [x] Namespaced lowercase id outside `omarchy.*`: `io.github.crucialjun.aula-sc580`
- [x] No symlinks in the tree (`omarchy plugin validate .` passes)
- [ ] Public GitHub repository at the root URL (no `/tree/main`)
- [ ] Optional `preview.png` at the root — a screenshot of the open panel (any size; the marketplace optimises it)
- [ ] The plugin id must match your GitHub user: if your account isn't `crucialjun`, change it everywhere first:
      `grep -rl "io.github.crucialjun" --exclude-dir=.git . | xargs sed -i 's/io.github.crucialjun/io.github.YOURNAME/g'`

## 1. Push the repo

```sh
gh repo create omarchy-sc580 --public --source . --push
# or: git remote add origin git@github.com:YOURNAME/omarchy-sc580.git && git push -u origin main
```

Then sanity-check it the way the marketplace will: install from the URL on a
clean Omarchy and open the panel.

```sh
omarchy plugin add https://github.com/YOURNAME/omarchy-sc580 --enable
omarchy plugin validate ~/.config/omarchy/plugins/io.github.YOURNAME.aula-sc580
```

## 2. Submit

Either the issue form
https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml
or from the CLI with the body below (keep the six headings, their order and
the exact checklist text — the bot parses them):

```sh
cat > /tmp/omarchy-plugin-submission.md <<'EOF'
### Repository URL

https://github.com/crucialjun/omarchy-sc580

### Category

Hardware

### Tags

bar, quickshell, power-management

### Suggest a missing tag

mouse

### Maintainer notes

Configures the AULA SC580 / SC580X gaming mouse (battery, DPI, polling rate, sleep, button remapping) over its vendor HID interface; protocol reverse-engineered from the Windows configurator (PROTOCOL.md). Dependencies: python3 standard library only, bundled in bin/. The mouse's hidraw node needs a udev rule (udev/70-aula-sc580.rules, two USB IDs with TAG+="uaccess"); the panel offers to install it via pkexec, which is the only privileged action. No network access. Writes only ~/.config/sc580/config.json.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
EOF

gh issue create \
  --repo omacom/omarchy-plugin-marketplace \
  --title "[Plugin]: AULA SC580 Mouse" \
  --body-file /tmp/omarchy-plugin-submission.md
```

Allowed categories: Appearance, Desktop, Developer Tools, Hardware, Kids,
Productivity, System, Widgets, Other. Allowed tags (1–3): ai, bar, education,
games, hyprland, kids, launcher, media, power-management, quickshell, security,
system, vpn, workspaces.

## 3. What the bot will say

Two bot comments appear on the issue: compatibility validation and the
**Automated Security Baseline**. Expect the baseline to report the
`privilege` capability (the `pkexec`/`sudo` udev step) and possibly
`installer` (`install.sh`) — these are *review-required*, not blocking; a
maintainer accepts them after reading the notes above. Fix anything it calls
`needs-fixes` in the repo, then edit the issue (that re-runs validation); don't
open a second issue.

## 4. Updating a listing

Bump `version` in `manifest.json`, push, then open the
[Plugin verification form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml),
choose **Verify and publish a newer upstream commit**, and give the plugin id,
repo URL and the full 40-character commit SHA (`git rev-parse HEAD`).
