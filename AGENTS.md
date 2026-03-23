# Landing Page Maintenance

This branch (`gh-pages`) contains the GitHub Pages landing page for Equaliser.

## Updating Assets

When updating the landing page for a new release:

### Screenshots

Copy from main branch:
```bash
# From gh-pages branch, checkout screenshots from main:
git checkout main -- docs/user/images/equalisaer-menu-bar.png
git checkout main -- docs/user/images/equalisaer-main-window.png

# Move to assets with simplified names:
mv docs/user/images/equalisaer-menu-bar.png assets/menu-bar.png
mv docs/user/images/equalisaer-main-window.png assets/main-window.png
rmdir -p docs/user/images 2>/dev/null || true
```

### App Icon

```bash
git checkout main -- resources/AppIcon.svg
mv resources/AppIcon.svg assets/AppIcon.svg
rmdir resources 2>/dev/null || true
```

## Updating Version

Edit `index.html` and update the version in the footer (line ~87):

```html
<span>Version X.Y.Z</span>
```

Match the version to the release tag (e.g., `1.2.0`).

## Cache Busting

Asset URLs include a git hash query string to ensure returning visitors get fresh content after updates. The hash is automatically updated by the deploy script.

Example URLs:
```
href="style.css?d6db879"
src="assets/menu-bar.png?d6db879"
```

## Deployment Workflow

```bash
# 1. Update assets from main branch (if needed)
git checkout main -- docs/user/images/...

# 2. Update version in index.html (if needed)
# Edit the version number in the footer

# 3. Run deploy script to update cache buster
./deploy.sh

# 4. Review changes
git diff

# 5. Commit and push
git add -A
git commit -m "Update landing page for v1.2.0"
git push origin gh-pages
```

The deploy script (`deploy.sh`) automatically:
- Gets the current git hash from the gh-pages branch
- Updates all asset URLs in `index.html` with the new hash

## File Structure

```
gh-pages/
├── AGENTS.md          # This file
├── deploy.sh          # Deploy script (cache buster update)
├── index.html         # Landing page
├── style.css          # Styles
└── assets/
    ├── AppIcon.svg    # App icon (from main: resources/AppIcon.svg)
    ├── menu-bar.png   # Menu bar screenshot
    └── main-window.png # Main window screenshot
```

## Live URL

https://knage.net/equaliser/