.PHONY: build
build:
	forge build

.PHONY: deploy
deploy: build
	# NOTE: for deployment RAW_PRIVATE_KEY is needed!
	npx ts-node -T scripts/deploy.ts
