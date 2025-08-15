-include .env

.PHONY: deploy

deploy:
	@forge script script/DeployTerraEngine.s.sol:DeployTerraEngine --rpc-url $(ANVIL_URL) --private-key $(ANVIL_KEY) --broadcast