.PHONY: all service-worker dev release gh-pages serve cleanup

# Ensure `cd` works properly by forcing everything to be executed in a single shell.
.ONESHELL:

all: src/KaTeX src/icon-192.png src/icon-512.png src/Workbox/workbox-window.prod.mjs

# Vendor KaTeX dependencies.
src/KaTeX:
	set -e
	curl -L -O "https://github.com/KaTeX/KaTeX/releases/download/v0.16.9/katex.zip"
	unzip katex.zip
	rm katex.zip
	mv katex src/KaTeX

# Vendor any workbox dependency.
src/Workbox/workbox-%:
	mkdir -p $(@D)
	curl -L -o $@ https://storage.googleapis.com/workbox-cdn/releases/7.0.0/workbox-$*
	curl -L -o $@.map https://storage.googleapis.com/workbox-cdn/releases/7.0.0/workbox-$*.map

# Build service worker.
service-worker: service-worker/build.js
	cd $(dir $<)
	if [ ! -z "$$NVM_DIR" ]; then . $$NVM_DIR/nvm.sh; fi
	nvm use 20 && npm install && node build.js

# Generate icons required by the webapp manifest. Requires ImageMagick.
src/icon-512.png: src/icon.png
	convert $< -background none -resize 512x512 $@
src/icon-192.png: src/icon.png
	convert $< -background none -resize 192x192 $@

# Update the `dev` branch from `master`.
dev:
	set -e
	git checkout dev
	git rebase master
	git checkout @{-1}

# Update the `release` branch from `dev`, and build the service worker.
release:
	set -e
	git checkout release
	git rebase dev
	make service-worker
	git checkout @{-1}

# Update the quiver GitHub Pages application.
gh-pages:
	# We use several branches for the deployment workflow.
	# - `master`: Main development branch.
	# - `release`: The branch that is used for hosting on GitHub Pages.
	# - `dev`: The branch that is hosted under /dev on GitHub Pages.
	# - `squash`: A temporary branch containing squashed versions of `release` and `dev`.
	# - `gh-pages`: The branch that is actually hosted directly. This includes `release` and `dev`.

	# Terminate if there are any errors. We may have to do some manual cleanup in this case, but
	# it's better than trying to push a broken version of quiver.
	set -e
	BASE_DIR=$$PWD
	# Store the name of the current branch, to return to it after completing this process.
	CURRENT=$$(git rev-parse --abbrev-ref HEAD)
	# Checkout the release branch.
	git checkout release
	# Get the initial commit ID, which will be used for squashing history.
	TAIL=$$(git rev-list --max-parents=0 HEAD)
	# Copy the release branch on to a new branch, for squashing purposes.
	git checkout -b squashed
	# Squash all the history (excluding the fixed, initial commit). This will improve performance
	# for `subtree split` later, which has to iterate through the entire history of the branch.
	git reset $$TAIL
	git add -A
	git commit --allow-empty -m "Add release branch"
	# Split off the `src/` directory into its own branch.
	RELEASE=$$(git subtree split --prefix=src)

	# Checkout the GitHub Pages branch in a new worktree. We use a new worktree because the branch
	# is essentially incomparable with the other branches and we don't want to get any git conflicts
	# from switching incompatible branches.
	git worktree add ../quiver-worktree gh-pages
	cd ../quiver-worktree
	# Reset the GitHub Pages branch so that it contains the release source code.
	git reset --hard $$RELEASE
	# Copy KaTeX into the main release directory.
	cp -r $$BASE_DIR/src/KaTeX .
	# Copy the service worker and its dependencies into the main release directory.
	cp -r $$BASE_DIR/src/Workbox .
	cp $$BASE_DIR/src/service-worker.js .
	SW_DEPENDENCY=$$(find $$BASE_DIR/src -type f -name "workbox-*.js")
	cp $$SW_DEPENDENCY .
	cp $$BASE_DIR/src/icon-512.png .
	cp $$BASE_DIR/src/icon-192.png .

	git add .
	git commit -m "Summary commit"
	# Push to the remote `gh-pages` branch, which will trigger a rebuild on GitHub Pages.
	git push --force

	# Navigate back to the main working tree.
	cd ../quiver
	# Remove the temporary worktree.
	git worktree remove ../quiver-worktree -f
	# Checkout the original branch.
	git checkout $$CURRENT
	# Delete the temporary `squashed` branch.
	git branch -D squashed

serve:
	python3 -m http.server -d src/

# Clean up the effects of the gh-pages upload, if it did not successfully terminate.
cleanup:
	git checkout master
	git worktree remove ../quiver-worktree -f
	rm -r ../quiver-worktree
	git branch -D squashed
