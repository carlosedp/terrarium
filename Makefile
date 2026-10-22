# terrarium: common tasks. `make` lists them.

PORT  ?= 8800
NORNS ?= we@norns.local
DEST  ?= /home/we/dust/code/terrarium
MIUGENS ?= ../norns-mi-UGens

.DEFAULT_GOAL := help
.PHONY: help web norns-web stop test soak build clean deploy manual-images manual-pdf mi-wasm logo

help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  make %-14s %s\n", $$1, $$2 }'

# "[s]erve.mjs" can't match pkill's own shell, which "serve.mjs" would (and kill it)
web: stop ## run the script in the browser, reloading on save (http://localhost:8800/, or PORT=...)
	node tools/norns-web/serve.mjs . $(PORT)

norns-web: web

stop: ## stop a running norns-web server
	-@pkill -f "[s]erve.mjs" || true

test: ## headless smoke test of the Lua side
	lua test/smoke.lua

soak: ## hours of jar time headless, looking for leaks and stuck states (HOURS=8, ~1.5 min each)
	lua test/soak.lua $(or $(HOURS),8)

build: ## static copy of norns-web in tools/norns-web/dist (to publish)
	node tools/norns-web/build.mjs --cdn

clean: ## remove the static copy
	rm -rf tools/norns-web/dist

# copies the script to the norns over ssh (NORNS=we@<ip> if norns.local doesn't resolve);
# then load it from the norns menu or maiden
deploy: test ## copy the script to the norns (needs ssh access)
	rsync -av --delete --exclude '.*' --exclude tools --exclude test --exclude doc --exclude '*.js' \
		--exclude Makefile --exclude 'Engine_Terrarium/' ./ $(NORNS):$(DEST)/

manual-images: ## re-render the manual's scene pictures (doc/img) from the Lua
	@mkdir -p tools/manual/pgm
	lua tools/manual/lib/shots.lua . tools/manual/pgm > /dev/null
	python3 tools/manual/topng.py tools/manual/pgm doc/img

logo: ## draw the mark (doc/img/icon.svg, logo.svg, icon-touch.svg and its 180 px PNG)
	python3 tools/manual/logo.py doc/img
	@[ -d tools/manual/node_modules ] || npm --prefix tools/manual install --no-fund --no-audit
	node tools/manual/svg2png.mjs doc/img/icon-touch.svg doc/img/icon-touch.png 180

manual-pdf: ## build doc/terrarium-manual.pdf from doc/MANUAL.md (node + a Chromium)
	@[ -d tools/manual/node_modules ] || npm --prefix tools/manual install --no-fund --no-audit
	node tools/manual/pdf.mjs

# the browser's engine plays mi-UGens built as WebAssembly by norns-mi-UGens (podman or docker)
mi-wasm: ## rebuild lib/Engine_Terrarium/ (the browser's mi-UGens) from norns-mi-UGens (MIUGENS=...)
	cd $(MIUGENS) && ./build.sh --wasm --pr 24
	cp $(MIUGENS)/work/out-wasm/*.wasm $(MIUGENS)/work/out-wasm/mi-ugens.js \
		$(MIUGENS)/work/out-wasm/mi-ugens-node.js $(MIUGENS)/work/out-wasm/BUILDINFO lib/Engine_Terrarium/
	chmod -x lib/Engine_Terrarium/*
