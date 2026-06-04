.PHONY: molecule-test molecule-role-tests molecule-role-%

MOLECULE_ROLE_DIRS := $(sort $(dir $(wildcard ansible/roles/*/molecule/*/molecule.yml)))

molecule-test: molecule-role-tests

molecule-role-tests:
	@set -e; \
	for scenario_dir in $(MOLECULE_ROLE_DIRS); do \
		role_dir=$${scenario_dir%/molecule/*/}; \
		scenario=$${scenario_dir%/}; scenario=$${scenario##*/}; \
		echo "==> $$role_dir :: $$scenario"; \
		(cd $$role_dir && uv run --project ../../.. molecule test -s $$scenario); \
	done

molecule-role-%:
	cd ansible/roles/$* && uv run --project ../../.. molecule test
