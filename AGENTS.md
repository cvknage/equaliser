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

## Live URL

https://knage.net/equaliser/

## Documentation

The site has a documentation hub (`docs.html`) with individual guides in the `docs/` directory.

### Structure

- `docs.html` - Hub page with cards linking to guides
- `docs/eq-presets-guide.html` - EQ Presets Guide (converted from main branch markdown)

### Syncing Documentation

To update the EQ Presets Guide from the main branch:

1. **Extract the markdown from main branch:**
   ```bash
   git show main:docs/user/EQ-Presets-Guide.md > /tmp/EQ-Presets-Guide.md
   ```

2. **Convert to HTML using pandoc:**
   ```bash
   pandoc /tmp/EQ-Presets-Guide.md --from markdown --to html --wrap=none --output docs-content-raw.html
   ```

3. **Fix Mermaid blocks:**
   - Replace `<pre class="mermaid"><code>` with `<pre class="mermaid">`
   - Replace `</code></pre>` with `</pre>`
   - Replace `&quot;` with `"`
   - Replace `--&gt;` with `-->`

4. **Update docs/eq-presets-guide.html:**
   - Open `docs/eq-presets-guide.html`
   - Replace the content inside `<main class="docs-content">` with the converted HTML
   - Keep the header, navigation, and footer
   - Note: Paths use `../` prefix (e.g., `../style.css`, `../assets/`)

5. **Run deploy script to update cache buster:**
   ```bash
   ./deploy.sh
   ```

### Adding New Documentation

To add a new documentation page:

1. **Create the HTML file in `docs/` directory:**
   - Copy `docs/eq-presets-guide.html` as a template
   - Update title, description, and content
   - Ensure paths use `../` prefix for assets

2. **Add a card to `docs.html` hub page:**
   ```html
   <a href="docs/your-guide.html" class="doc-card">
       <h2>Your Guide Title</h2>
       <p>Description of your guide...</p>
       <span class="card-arrow">Read guide →</span>
   </a>
   ```

3. **Run deploy script:**
   ```bash
   ./deploy.sh
   ```

## File Structure

```
gh-pages/
├── CLAUDE.md          # This file
├── deploy.sh          # Deploy script (cache buster update)
├── index.html         # Landing page
├── docs.html          # Documentation hub page
├── docs/              # Documentation guides
│   └── eq-presets-guide.html
├── style.css          # Styles
└── assets/
    ├── AppIcon.svg    # App icon (from main: resources/AppIcon.svg)
    ├── menu-bar.png   # Menu bar screenshot
    └── main-window.png # Main window screenshot
```