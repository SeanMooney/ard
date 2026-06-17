.DEFAULT_GOAL := default

.PHONY: \
	default render apply ping ssh ssh-print deploy verify destroy destroy-clean-generated clean-generated cleanup site \
	molecule-test molecule-role-tests molecule-role-%

ARD_PROVIDER ?= libvirt
ARD_DEPLOYMENT ?= devstack-1
ARD_DEPLOYMENTS_DIR ?= $(CURDIR)/deployments
ARD_USER ?= $(shell whoami)
ARD_KUBEVIRT_NAMESPACE ?=

# Deployment name incorporates user prefix for shared-tenancy providers
ARD_DEPLOYMENT_NAME_kubevirt = $(ARD_USER)-$(ARD_DEPLOYMENT)
ARD_DEPLOYMENT_NAME_libvirt = $(ARD_DEPLOYMENT)
ARD_DEPLOYMENT_NAME_static = $(ARD_DEPLOYMENT)
ARD_DEPLOYMENT_NAME = $(or $(ARD_DEPLOYMENT_NAME_$(ARD_PROVIDER)),$(ARD_DEPLOYMENT))

ARD_DEPLOYMENT_DIR ?= $(ARD_DEPLOYMENTS_DIR)/$(ARD_DEPLOYMENT_NAME)
ARD_WORKLOAD ?= devstack
ARD_DEVSTACK_SERVICES = devstack,ovn,tempest
ARD_TOPOLOGY ?= $(if $(filter microshift,$(ARD_WORKLOAD)),microshift-single-node,one-controller-one-compute)
ARD_TARGET_BRANCH ?= master
ARD_SERVICES ?= $(if $(filter microshift,$(ARD_WORKLOAD)),,$(ARD_DEVSTACK_SERVICES))
ARD_PROVIDER_PROFILE ?= local-libvirt
ARD_IMAGE ?= $(if $(filter microshift,$(ARD_WORKLOAD)),centos-stream-10,)
ARD_NETWORK_CIDR ?= 192.168.96.0/24
ARD_RENDER_FILE ?=
ARD_EXTRA_VARS ?=
ARD_NODE ?= controller
ARD_SSH_PRINT ?= 0
ARD_SSH_ARGS ?=

ARD_RENDER_FILE_ARG = $(if $(ARD_RENDER_FILE),-e @$(ARD_RENDER_FILE),)
ARD_RENDER_PROVIDER_VAR = $(if $(filter command line environment override,$(origin ARD_PROVIDER)),ard_provider=$(ARD_PROVIDER),)
ARD_RENDER_PROVIDER_PROFILE_VAR = $(if $(filter command line environment override,$(origin ARD_PROVIDER_PROFILE)),ard_provider_profile=$(ARD_PROVIDER_PROFILE),)
ARD_RENDER_TARGET_BRANCH_VAR = $(if $(filter command line environment override,$(origin ARD_TARGET_BRANCH)),ard_target_branch=$(ARD_TARGET_BRANCH),)
ARD_RENDER_TOPOLOGY_VAR = $(if $(filter microshift,$(ARD_WORKLOAD)),ard_topology=$(ARD_TOPOLOGY),$(if $(filter command line environment override,$(origin ARD_TOPOLOGY)),ard_topology=$(ARD_TOPOLOGY),))
ARD_RENDER_SERVICES_VAR = $(if $(filter microshift,$(ARD_WORKLOAD)),ard_service_profiles=,$(if $(filter command line environment override,$(origin ARD_SERVICES)),ard_service_profiles=$(ARD_SERVICES),))
ARD_RENDER_IMAGE_VAR = $(if $(ARD_IMAGE),ard_render_image=$(ARD_IMAGE),)
ARD_RENDER_NETWORK_VAR = $(if $(filter command line environment override,$(origin ARD_NETWORK_CIDR)),ard_libvirt_network_cidr=$(ARD_NETWORK_CIDR),)

ARD_KUBEVIRT_EXTRA_VARS = \
	$(if $(ARD_KUBEVIRT_NAMESPACE),ard_kubevirt_namespace=$(ARD_KUBEVIRT_NAMESPACE),)

ARD_RENDER_EXTRA_VARS = \
	ard_deployment_dir=$(ARD_DEPLOYMENT_DIR) \
	ard_user=$(ARD_USER) \
	$(ARD_RENDER_PROVIDER_VAR) \
	$(ARD_RENDER_PROVIDER_PROFILE_VAR) \
	$(ARD_RENDER_TARGET_BRANCH_VAR) \
	$(ARD_RENDER_TOPOLOGY_VAR) \
	$(ARD_RENDER_SERVICES_VAR) \
	$(ARD_RENDER_IMAGE_VAR) \
	$(ARD_RENDER_NETWORK_VAR) \
	$(if $(filter kubevirt,$(ARD_PROVIDER)),$(ARD_KUBEVIRT_EXTRA_VARS),) \
	$(ARD_EXTRA_VARS)

ARD_DEPLOYMENT_EXTRA_VARS = \
	ard_deployment_dir=$(ARD_DEPLOYMENT_DIR) \
	$(ARD_EXTRA_VARS)

ARD_DEPLOY_PLAYBOOK_devstack = ansible/playbooks/provider/deploy-devstack.yaml
ARD_DEPLOY_PLAYBOOK_microshift = ansible/playbooks/workloads/microshift/deploy.yaml
ARD_DEPLOY_PLAYBOOK_oko = ansible/playbooks/workloads/oko/deploy.yaml
ARD_DEPLOY_PLAYBOOK = $(ARD_DEPLOY_PLAYBOOK_$(ARD_WORKLOAD))

default:
	-$(MAKE) destroy-clean-generated
	-$(MAKE) cleanup
	$(MAKE) render
	$(MAKE) apply
	$(MAKE) ping
	$(MAKE) deploy
	$(MAKE) verify

render:
	uv run ansible-playbook -i localhost, ansible/playbooks/provider/render.yaml \
		$(ARD_RENDER_FILE_ARG) \
		-e "$(ARD_RENDER_EXTRA_VARS)"

apply:
	uv run ansible-playbook -i localhost, ansible/playbooks/provider/apply.yaml \
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
	$(if $(ARD_DEPLOY_PLAYBOOK),,$(error Unsupported ARD_WORKLOAD '$(ARD_WORKLOAD)'))
	uv run ansible-playbook -i $(ARD_DEPLOYMENT_DIR)/inventory.yaml \
		$(ARD_DEPLOY_PLAYBOOK) \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

verify:
	uv run ansible-playbook -i localhost, ansible/playbooks/provider/verify.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

destroy:
	uv run ansible-playbook -i localhost, ansible/playbooks/provider/destroy.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS)"

destroy-clean-generated:
	uv run ansible-playbook -i localhost, ansible/playbooks/provider/destroy.yaml \
		-e "$(ARD_DEPLOYMENT_EXTRA_VARS) ard_destroy_cleanup_generated=true"

clean-generated:
	rm -rf $(ARD_DEPLOYMENT_DIR)/inventory.yaml \
		$(ARD_DEPLOYMENT_DIR)/provider-state.yaml \
		$(ARD_DEPLOYMENT_DIR)/rendered

cleanup:
	uv run ansible-playbook -i localhost, ansible/playbooks/provider/cleanup.yaml \
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
