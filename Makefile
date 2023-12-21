.PHONY: build
build:
	forge build

.PHONY: deploy
deploy: build
	npx ts-node -T scripts/deploy.ts

.PHONY: configure_all_tcbinfos
configure_all_tcbinfos:
	# Non-PHONY! If needed, clear it manually
	cd lib/sgx-tcbInfos && make
	export TCB_INFO_FILES="$(shell find ./lib/sgx-tcbInfos/assets -name "tcbinfo.json" -printf "%p ")"; \
	npx ts-node -T scripts/configure_tcbinfo.ts
