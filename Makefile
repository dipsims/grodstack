########################################################################################################################
#
# When adding a new target:
#   - If you are adding a new service make sure the prod.reset target will fully reset said service.
#
########################################################################################################################
.DEFAULT_GOAL := help

.PHONY: analytics-pipeline-devstack-test analytics-pipeline-shell \
        analyticspipeline-shell backup build-courses check-memory \
        create-test-course credentials-shell destroy prod.cache-programs \
        prod.check prod.checkout prod.clone prod.clone.ssh prod.nfs.setup \
        devpi-password prod.provision prod.provision.analytics_pipeline \
        prod.provision.services prod.provision.xqueue prod.pull prod.repo.reset \
        prod.reset prod.status prod.sync.daemon.start prod.sync.provision \
        prod.sync.requirements prod.sync.up prod.up prod.up.all \
        prod.up.analytics_pipeline prod.up.watchers prod.up.with-programs \
        discovery-shell down e2e-shell e2e-tests ecommerce-shell \
        feature-toggle-state forum-restart-devserver healthchecks help \
        lms-restart lms-shell lms-static lms-update-db lms-watcher-shell logs \
        mongo-shell mysql-shell mysql-shell-edxapp provision pull \
        pull.analytics_pipeline pull.xqueue registrar-shell requirements \
        restore selfcheck static stats stop stop.all stop.analytics_pipeline \
        stop.watchers stop.xqueue studio-restart studio-shell studio-static \
        studio-update-db studio-watcher-shell update-db upgrade upgrade \
        validate validate-lms-volume vnc-passwords xqueue_consumer-restart \
        xqueue_consumer-shell xqueue-restart xqueue-shell

# Include options (configurable through options.local.mk)
include options.mk

# Include local overrides to options.
# You can use this file to configure your Devstack. It is ignored by git.
-include options.local.mk  # Prefix with hyphen to tolerate absence of file.

# Include local makefile with additional targets.
-include local.mk  # Prefix with hyphen to tolerate absence of file.

# Docker Compose YAML files to define services and their volumes.
# Depending on the value of FS_SYNC_STRATEGY, we use a slightly different set of
# files, enabling use of different strategies to synchronize files between the host and
# the containers.
# Some services are only available for certain values of FS_SYNC_STRATEGY.
# For example, the LMS/Studio asset watchers are only available for local-mounts and nfs,
# and XQueue and the Analytics Pipeline are only available for local-mounts.

ifeq ($(FS_SYNC_STRATEGY),local-mounts)
DOCKER_COMPOSE_FILES := \
-f docker-compose-host.yml \
-f docker-compose-themes.yml \
-f docker-compose-xqueue.yml \
-f docker-compose-analytics-pipeline.yml \
-f docker-compose-marketing-site.yml
endif

# All three filesystem synchronization strategy require the main docker-compose.yml file.
DOCKER_COMPOSE_FILES := -f docker-compose.yml $(DOCKER_COMPOSE_FILES)

OS := $(shell uname)

# Need to run some things under winpty in a Windows git-bash shell
# (but not when calling bash from a command shell or PowerShell)
ifneq (,$(MINGW_PREFIX))
    WINPTY := winpty
else
    WINPTY :=
endif

# Don't try redirecting to /dev/null in any Windows shell
ifneq (,$(findstring MINGW,$(OS)))
    DEVNULL :=
else
    DEVNULL := >/dev/null
endif

# Include specialized Make commands.
include marketing.mk

# Export Makefile variables to recipe shells.
export

# Generates a help message. Borrowed from https://github.com/pydanny/cookiecutter-djangopackage.
help: ## Display this help message
	@echo "Please use \`make <target>' where <target> is one of"
	@awk -F ':.*?## ' '/^[a-zA-Z]/ && NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

requirements: ## Install requirements
	pip install -r requirements/base.txt

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: ## Upgrade requirements with pip-tools
	pip install -qr requirements/pip-tools.txt
	pip-compile --upgrade -o requirements/pip-tools.txt requirements/pip-tools.in
	pip-compile --upgrade -o requirements/base.txt requirements/base.in

prod.clone.ssh: ## Clone service repos using SSH method to the parent directory
	./repo.sh clone_ssh
	# ./openedx/build.sh
	# ./commerce/build.sh
	# ./credentials/build.sh

prod.provision.services: ## Provision default services with local mounted directories
	# We provision all default services as well as 'e2e' (end-to-end tests).
	# e2e is not part of `DEFAULT_SERVICES` because it isn't a service;
	# it's just a way to tell ./provision.sh that the fake data for end-to-end
	# tests should be prepared.
	$(WINPTY) bash ./provision.sh $(DEFAULT_SERVICES)

prod.provision.services.%: ## Provision specified services with local mounted directories, separated by plus signs
	$(WINPTY) bash ./provision.sh $*

prod.provision: check-memory prod.clone.ssh prod.provision.services stop ## Provision dev environment with default services, and then stop them.

prod.cache-programs: ## Copy programs from Discovery to Memcached for use in LMS.
	$(WINPTY) bash ./programs/provision.sh cache

prod.provision.xqueue: prod.provision.services.xqueue

prod.reset: down prod.repo.reset pull prod.up static update-db ## Attempts to reset the local devstack to the master working state

prod.status: ## Prints the status of all git repositories
	$(WINPTY) bash ./repo.sh status

prod.repo.reset: ## Attempts to reset the local repo checkouts to the master working state
	$(WINPTY) bash ./repo.sh reset

prod.pull: prod.pull.$(DEFAULT_SERVICES) ## Pull Docker images required by default services.

prod.pull.without-deps.%: ## Pull latest Docker images for services (separated by plus-signs).
	docker-compose $(DOCKER_COMPOSE_FILES) pull $$(echo $* | tr + " ")

prod.pull.%: ## Pull latest Docker images for services (separated by plus-signs) and all their dependencies.
	docker-compose $(DOCKER_COMPOSE_FILES) pull --include-deps $$(echo $* | tr + " ")

prod.up: prod.up.$(DEFAULT_SERVICES) check-memory ## Bring up default services.

prod.up.%: | check-memory ## Bring up specific services (separated by plus-signs) and their dependencies with host volumes.
	docker-compose $(DOCKER_COMPOSE_FILES) up -d $$(echo $* | tr + " ")
ifeq ($(ALWAYS_CACHE_PROGRAMS),true)
	make prod.cache-programs
endif

prod.up.without-deps.%:  ## Bring up specific services (separated by plus-signs) without dependencies.
	docker-compose $(DOCKER_COMPOSE_FILES) up --d --no-deps $$(echo $* | tr + " ")

prod.up.with-programs: prod.up prod.cache-programs  ## Bring up a all services and cache programs in LMS.

prod.up.with-programs.%: prod.up.$* prod.cache-programs ## Bring up a service and its dependencies and cache programs in LMS.

prod.up.watchers: check-memory prod.up.lms_watcher+studio_watcher ## Bring up asset watcher containers

prod.nfs.setup:  ## Sets up an nfs server on the /Users folder, allowing nfs mounting on docker
	./setup_native_nfs_docker_osx.sh

prod.nfs.%:
	FS_SYNC_STRATEGY=nfs make prod.$*

prod.up.all: prod.up prod.up.watchers ## Bring up all services with host volumes, including watchers

# TODO: Improve or rip out Docker Sync targets.
#       They are not well-fleshed-out and it is not clear if anyone uses them.

prod.sync.daemon.start: ## Start the docker-sycn daemon
	docker-sync start

prod.sync.provision: prod.sync.daemon.start ## Provision with docker-sync enabled
	FS_SYNC_STRATEGY=docker-sync make prod.provision

prod.sync.requirements: ## Install requirements
	gem install docker-sync

prod.sync.up: prod.sync.daemon.start ## Bring up all services with docker-sync enabled
	FS_SYNC_STRATEGY=docker-sync make prod.up

prod.check: prod.check.$(DEFAULT_SERVICES) ## Run checks for the default service set.

prod.check.%:  # Run checks for a given service or set of services (separated by plus-signs).
	$(WINPTY) bash ./check.sh $*

provision: | prod.provision ## This command will be deprecated in a future release, use prod.provision
	echo "\033[0;31mThis command will be deprecated in a future release, use prod.provision\033[0m"

stop: ## Stop all services
	(test -d .docker-sync && docker-sync stop) || true ## Ignore failure here
	docker-compose stop

stop.watchers: ## Stop asset watchers
	docker-compose $(DOCKER_COMPOSE_FILES) stop lms_watcher studio_watcher

stop.all: | stop.analytics_pipeline stop stop.watchers ## Stop all containers, including asset watchers

stop.xqueue: ## Stop the XQueue and XQueue-Consumer containers
	docker-compose $(DOCKER_COMPOSE_FILES) stop xqueue xqueue_consumer

down: ## Remove all service containers and networks
	(test -d .docker-sync && docker-sync clean) || true ## Ignore failure here
	docker-compose $(DOCKER_COMPOSE_FILES) down

destroy: ## Remove all devstack-related containers, networks, and volumes
	$(WINPTY) bash ./destroy.sh

logs: ## View logs from containers running in detached mode
	docker-compose $(DOCKER_COMPOSE_FILES) logs -f

%-logs: ## View the logs of the specified service container
	docker-compose $(DOCKER_COMPOSE_FILES) logs -f --tail=500 $*

RED="\033[0;31m"
YELLOW="\033[0;33m"
GREY="\033[1;90m"
NO_COLOR="\033[0m"

pull: prod.pull
	@echo -n $(RED)
	@echo "******************* PLEASE NOTE ********************************"
	@echo -n $(YELLOW)
	@echo "The 'make pull' command is deprecated."
	@echo "Please use 'make prod.pull.<service>'."
	@echo "It will pull all the images that the given serivce depends upon."
	@echo "Example: "
	@echo "----------------------------------"
	@echo -n $(GREY)
	@echo "~/devstack$$ make prod.pull.lms"
	@echo "   Pulling memcached     ... done"
	@echo "   Pulling mongo         ... done"
	@echo "   Pulling mysql         ... done"
	@echo "   Pulling elasticsearch ... done"
	@echo "   Pulling discovery     ... done"
	@echo "   Pulling forum         ... done"
	@echo "   Pulling devpi         ... done"
	@echo "   Pulling lms           ... done"
	@echo "~/devstack$$"
	@echo -n $(YELLOW)
	@echo "----------------------------------"
	@echo "If you must pull all images, such as for initial"
	@echo "provisioning, run 'make prod.pull'."
	@echo -n $(RED)
	@echo "****************************************************************"
	@echo -n $(NO_COLOR)

pull.xqueue: prod.pull.without-deps.xqueue+xqueue_consumer

validate: ## Validate the devstack configuration
	docker-compose config

backup: prod.up.mysql+mongo+elasticsearch ## Write all data volumes to the host.
	docker run --rm --volumes-from edx.devstack.mysql -v $$(pwd)/.dev/backups:/backup debian:jessie tar zcvf /backup/mysql.tar.gz /var/lib/mysql
	docker run --rm --volumes-from edx.devstack.mongo -v $$(pwd)/.dev/backups:/backup debian:jessie tar zcvf /backup/mongo.tar.gz /data/db
	docker run --rm --volumes-from edx.devstack.elasticsearch -v $$(pwd)/.dev/backups:/backup debian:jessie tar zcvf /backup/elasticsearch.tar.gz /usr/share/elasticsearch/data

restore: prod.up.mysql+mongo+elasticsearch ## Restore all data volumes from the host. WARNING: THIS WILL OVERWRITE ALL EXISTING DATA!
	docker run --rm --volumes-from edx.devstack.mysql -v $$(pwd)/.dev/backups:/backup debian:jessie tar zxvf /backup/mysql.tar.gz
	docker run --rm --volumes-from edx.devstack.mongo -v $$(pwd)/.dev/backups:/backup debian:jessie tar zxvf /backup/mongo.tar.gz
	docker run --rm --volumes-from edx.devstack.elasticsearch -v $$(pwd)/.dev/backups:/backup debian:jessie tar zxvf /backup/elasticsearch.tar.gz

# TODO: Print out help for this target. Even better if we can iterate over the
# services in docker-compose.yml, and print the actual service names.
%-shell: ## Run a shell on the specified service container
	docker exec -it edx.devstack.$* /bin/bash

analyticspipeline-shell: ## Run a shell on the analytics pipeline container
	docker exec -it edx.devstack.analytics_pipeline env TERM=$(TERM) /edx/app/analytics_pipeline/devstack.sh open

credentials-shell: ## Run a shell on the credentials container
	docker exec -it edx.devstack.credentials env TERM=$(TERM) bash -c 'source /edx/app/credentials/credentials_env && cd /edx/app/credentials/credentials && /bin/bash'

discovery-shell: ## Run a shell on the discovery container
	docker exec -it edx.devstack.discovery env TERM=$(TERM) /edx/app/discovery/devstack.sh open

ecommerce-shell: ## Run a shell on the ecommerce container
	docker exec -it edx.devstack.ecommerce env TERM=$(TERM) /edx/app/ecommerce/devstack.sh open

e2e-shell: ## Start the end-to-end tests container with a shell
	docker run -it --network=devstack_default -v ${PROD_VOLUME}/edx-e2e-tests:/edx-e2e-tests -v ${PROD_VOLUME}/edx-platform:/edx-e2e-tests/lib/edx-platform --env-file ${PROD_VOLUME}/edx-e2e-tests/devstack_env edxops/e2e env TERM=$(TERM) bash

registrar-shell: ## Run a shell on the registrar site container
	docker exec -it edx.devstack.registrar env TERM=$(TERM) /edx/app/registrar/devstack.sh open

%-update-db: ## Run migrations for the specified service container
	docker exec -t edx.devstack.$* bash -c 'source /edx/app/$*/$*_env && cd /edx/app/$*/$*/ && make migrate'

studio-update-db: ## Run migrations for the Studio container
	docker exec -t edx.devstack.studio bash -c 'source /edx/app/edxapp/edxapp_env && cd /edx/app/edxapp/edx-platform/ && paver update_db'

lms-update-db: ## Run migrations LMS container
	docker exec -t edx.devstack.lms bash -c 'source /edx/app/edxapp/edxapp_env && cd /edx/app/edxapp/edx-platform/ && paver update_db'

update-db: | $(DB_MIGRATION_TARGETS) ## Run the migrations for DEFAULT_SERVICES

lms-shell: ## Run a shell on the LMS container
	docker exec -it edx.devstack.lms env TERM=$(TERM) /edx/app/edxapp/devstack.sh open

lms-restart: lms-restart-devserver

studio-shell: ## Run a shell on the Studio container
	docker exec -it edx.devstack.studio env TERM=$(TERM) /edx/app/edxapp/devstack.sh open

studio-restart: studio-restart-devserver

xqueue-shell: ## Run a shell on the XQueue container
	docker exec -it edx.devstack.xqueue env TERM=$(TERM) /edx/app/xqueue/devstack.sh open

xqueue-restart: xqueue-restart-devserver

xqueue_consumer-shell: ## Run a shell on the XQueue consumer container
	docker exec -it edx.devstack.xqueue_consumer env TERM=$(TERM) /edx/app/xqueue/devstack.sh open

xqueue_consumer-restart: ## Kill the XQueue development server. The watcher process will restart it.
	docker exec -t edx.devstack.xqueue_consumer bash -c 'kill $$(ps aux | grep "manage.py run_consumer" | egrep -v "while|grep" | awk "{print \$$2}")'

%-static: ## Rebuild static assets for the specified service container
	docker exec -t edx.devstack.$* bash -c 'source /edx/app/$*/$*_env && cd /edx/app/$*/$*/ && make static'

lms-static: ## Rebuild static assets for the LMS container
	docker exec -t edx.devstack.lms bash -c 'source /edx/app/edxapp/edxapp_env && cd /edx/app/edxapp/edx-platform/ && paver update_assets lms'

studio-static: ## Rebuild static assets for the Studio container
	docker exec -t edx.devstack.studio bash -c 'source /edx/app/edxapp/edxapp_env && cd /edx/app/edxapp/edx-platform/ && paver update_assets studio'

static: | credentials-static discovery-static ecommerce-static lms-static studio-static ## Rebuild static assets for all service containers

healthchecks: prod.check.$(DEFAULT_SERVICES)

healthchecks.%: prod.check.%

devpi-password: ## Get the root devpi password for the devpi container
	docker-compose exec devpi bash -c "cat /data/server/.serverpassword"

mysql-shell: ## Run a shell on the mysql container
	docker-compose exec mysql bash

mysql-shell-edxapp: ## Run a mysql shell on the edxapp database
	docker-compose exec mysql bash -c "mysql edxapp"

mongo-shell: ## Run a shell on the mongo container
	docker-compose exec mongo bash

check-memory: ## Check if enough memory has been allocated to Docker
	@if [ `docker info --format '{{.MemTotal}}'` -lt 2095771648 ]; then echo "\033[0;31mWarning, System Memory is set too low!!! Increase Docker memory to be at least 2 Gigs\033[0m"; fi || exit 0

stats: ## Get per-container CPU and memory utilization data
	docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

feature-toggle-state: ## Gather the state of feature toggles configured for various IDAs
	$(WINPTY) bash ./gather-feature-toggle-state.sh

selfcheck: ## check that the Makefile is well-formed
	@echo "The Makefile is well-formed."
