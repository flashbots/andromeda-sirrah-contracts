.PHONY: build
build:
	forge build --revert-strings debug

.PHONY: test
test:
	forge test --ffi

.PHONY: format
format:
	forge fmt .

.PHONY: deploy
deploy: build
	npx ts-node -T scripts/deploy.ts

.PHONY: bootstrap
bootstrap: build
	npx ts-node -T scripts/bootstrap_kettle.ts

.PHONY: onboard
onboard: build
	npx ts-node -T scripts/onboard_kettle.ts

.PHONY: test-examples
test-examples: build
	npx ts-node -T scripts/test_examples.ts

.PHONY: configure-all-tcbinfos
configure-all-tcbinfos:
	# Non-PHONY! If needed, clear it manually
	cd lib/sgx-tcbInfos && make
	export TCB_INFO_FILES="$(shell find ./lib/sgx-tcbInfos/assets -name "tcbinfo.json" -printf "%p ")"; \
	npx ts-node -T scripts/configure_tcbinfo.ts
