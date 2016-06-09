#!/bin/bash

## Contains configuration values for the Openstack cluster

# Stack name
STACK_NAME=${STACK_NAME:-KubernetesStack}

# Keypair for kubernetes stack
KUBERNETES_KEYPAIR_NAME=${KUBERNETES_KEYPAIR_NAME:-kubernetes_keypair}

NUMBER_OF_MINIONS=${NUMBER_OF_MINIONS:-1}

MAX_NUMBER_OF_MINIONS=${MAX_NUMBER_OF_MINIONS:-1}

MASTER_FLAVOR=${MASTER_FLAVOR:-m1.small}

MINION_FLAVOR=${MINION_FLAVOR:-m1.small}

EXTERNAL_NETWORK=${EXTERNAL_NETWORK:-public}

# Image id which will be used for kubernetes stack
IMAGE_ID=${IMAGE_ID:-81a2b65c-1d14-40f4-92b8-eb7b220eb87a}

# DNS server address
DNS_SERVER=${DNS_SERVER:-10.140.19.51}

# Public RSA key path
CLIENT_PUBLIC_KEY_PATH=${CLIENT_PUBLIC_KEY_PATH:-~/.ssh/id_rsa.pub}

# Max time period for stack provisioning. Time in minutes.
STACK_CREATE_TIMEOUT=${STACK_CREATE_TIMEOUT:-60}

# Private Docker registry url. Leave empty for default docker hub.
DOCKER_REGISTRY_URL=${DOCKER_REGISTRY_URL:-}

# Docker registry prefix for all k8s images.
DOCKER_REGISTRY_PREFIX=${DOCKER_REGISTRY_PREFIX:-}
