.DEFAULT_GOAL := default

.PHONY: \
	default render apply ping ssh ssh-print deploy verify destroy destroy-clean-generated clean-generated cleanup site \
	molecule-test molecule-role-tests molecule-role-%

ARD_PROVIDER ?= libvirt
ARD_DEPLOYMENT ?= devstack-1
ARD_DEPLOYMENTS_DIR ?= $(CURDIR)/deployments
ARD_DEPLOYMENT_DIR ?= $(ARD_DEPLOYMENTS_DIR)/$(ARD_DEPLOYMENT)
ARD_TOPOLOGY ?= one-controller-one-compute
ARD_IMAGE ?= debian-13
ARD_NETWORK_CIDR ?= 192.168.96.0/24
ARD_EXTRA_VARS ?=
ARD_NODE ?= controller
ARD_SSH_PRINT ?= 0
ARD_SSH_ARGS ?=

ARD_RENDER_EXTRA_VARS = \
	ard_provider=$(ARD_PROVIDER) \
	ard_deployment_dir=$(ARD_DEPLOYMENT_DIR) \
	ard_topology=$(ARD_TOPOLOGY) \
	ard_default_image=$(ARD_IMAGE) \
	ard_libvirt_network_cidr=$(ARD_NETWORK_CIDR) \
	$(ARD_EXTRA_VARS)

ARD_DEPLOYMENT_EXTRA_VARS = \
	ard_deployment_dir=$(ARD_DEPLOYMENT_DIR) \
	$(ARD_EXTRA_VARS)

default:
	-$(MAKE) destroy-clean-generated
	-$(MAKE) cleanup
	$(MAKE) render
	$(MAKE) apply
	$(MAKE) ping
	$(MAKE) deploy
	$(MAKE) verify

render:
	uv run ansible-playbook -i localhost, ansible/playbooks/ard-render.yaml \
		-e "$(ARD_RENDER_EXTRA_VARS)"

apply:
	uv run ansible-playbook -i localhost, ansible/playbooks/ard-apply.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

ping:
	uv run ansible -i $(ARD_DEPLOYMENT_DIR)/inventory.yaml all \
		-m ansible.builtin.ping

ssh:
	uv run scripts/ard-ssh \
		--inventory $(ARD_DEPLOYMENT_DIR)/inventory.yaml \
		--node $(ARD_NODE) \
		$(if $(filter 1 true yes,$(ARD_SSH_PRINT)),--print,) \
		$(if $(ARD_SSH_ARGS),-- $(ARD_SSH_ARGS),)

ssh-print:
	$(MAKE) ssh ARD_SSH_PRINT=1

deploy:
	uv run ansible-playbook -i $(ARD_DEPLOYMENT_DIR)/inventory.yaml \
		ansible/playbooks/ard-deploy-devstack.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

verify:
	uv run ansible-playbook -i localhost, ansible/playbooks/ard-verify.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

destroy:
	uv run ansible-playbook -i localhost, ansible/playbooks/ard-destroy.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

destroy-clean-generated:
	uv run ansible-playbook -i localhost, ansible/playbooks/ard-destroy.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS) ard_destroy_cleanup_generated=true"

clean-generated:
	rm -rf $(ARD_DEPLOYMENT_DIR)/inventory.yaml \
		$(ARD_DEPLOYMENT_DIR)/provider-state.yaml \
		$(ARD_DEPLOYMENT_DIR)/rendered

cleanup:
	uv run ansible-playbook -i localhost, ansible/playbooks/ard-cleanup.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

site: render apply deploy verify

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
