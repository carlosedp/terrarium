# terrarium: common tasks. `make` lists them.

PORT  ?= 8800
NORNS ?= we@norns.local
DEST  ?= /home/we/dust/code/terrarium

.DEFAULT_GOAL := help
.PHONY: help web norns-web stop test build clean submodules deploy

help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  make %-11s %s\n", $$1, $$2 }'

# "[s]erve.mjs" can't match pkill's own shell, which "serve.mjs" would (and kill it)
web: stop ## run the script in the browser (http://localhost:8800/, or PORT=...)
	node tools/norns-web/serve.mjs . $(PORT)

norns-web: web

stop: ## stop a running norns-web server
	-@pkill -f "[s]erve.mjs" || true

test: ## headless smoke test of the Lua side
	lua test/smoke.lua

build: ## static copy of norns-web in tools/norns-web/dist (to publish)
	node tools/norns-web/build.mjs --cdn

clean: ## remove the static copy
	rm -rf tools/norns-web/dist

submodules: ## fetch lib/nb after a clone without --recurse-submodules
	git submodule update --init

# copies the script to the norns over ssh (NORNS=we@<ip> if norns.local doesn't resolve);
# then load it from the norns menu or maiden
deploy: test ## copy the script to the norns (needs ssh access)
	rsync -av --delete --exclude '.*' --exclude tools --exclude test --exclude '*.js' \
		--exclude Makefile ./ $(NORNS):$(DEST)/
