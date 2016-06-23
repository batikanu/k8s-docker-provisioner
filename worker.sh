#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# A script to the k8s worker in docker containers.
# Authors @wizard_cxy @resouer

set -e

START_MODE=$1

init() {
	# Make sure docker daemon is running
	if ( ! ps -ef | grep "/usr/bin/docker" | grep -v 'grep' &> /dev/null  ); then
		echo "Docker is not running on this machine!"
		exit 1
	fi

	# Run as root
	if [ "$(id -u)" != "0" ]; then
		echo >&2 "Please run as root"
		exit 1
	fi

	# Make sure master ip is properly set
	if [ -z ${MASTER_IP} ]; then
		echo "Please export MASTER_IP in your env"
		exit 1
	fi

	# Make sure node ip is properly set
	if [ -z ${NODE_IP} ]; then
		NODE_IP=$(hostname -I | awk '{print $1}')
	fi

	# Set working mode
	if [[ -n ${START_MODE} && ${START_MODE} == "install" ]]; then
		echo "Start k8s cluster in installation mode"
		RESTART_POLICY="always"
	else
		echo "Start k8s cluster in run mode"
		RESTART_POLICY="no"
	fi

	# Make sure k8s images are properly set
	HYPERKUBE_IMAGE=${HYPERKUBE_IMAGE:-fest/hyperkube-amd64:latest}
	PAUSE_IMAGE=${PAUSE_IMAGE:-gcr.io/google_containers/pause:2.0}
	FLANNEL_IMAGE=${FLANNEL_IMAGE:-quay.io/coreos/flannel:0.5.5}

	# Add docker registry as prefix for k8s images.
	if [[ -n ${DOCKER_REGISTRY_PREFIX} ]]; then
		HYPERKUBE_IMAGE=${DOCKER_REGISTRY_PREFIX}/${HYPERKUBE_IMAGE}
		PAUSE_IMAGE=${DOCKER_REGISTRY_PREFIX}/${PAUSE_IMAGE}
		FLANNEL_IMAGE=${DOCKER_REGISTRY_PREFIX}/${FLANNEL_IMAGE}
	fi

	# Make sure k8s version env is properly set
	FLANNEL_IFACE=${FLANNEL_IFACE:-"eth0"}
	FLANNEL_IPMASQ=${FLANNEL_IPMASQ:-"true"}
	ARCH=${ARCH:-"amd64"}

	# Paths
	FLANNEL_SUBNET_DIR=${FLANNEL_SUBNET_DIR:-/run/flannel}

	# Constants
	TIMEOUT_FOR_SERVICES=20

	# Init variable
	DOCKER_CONF=""
	lsb_dist=""

	detect_lsb

	echo "FLANNEL_IFACE is set to: ${FLANNEL_IFACE}"
	echo "FLANNEL_IPMASQ is set to: ${FLANNEL_IPMASQ}"
	echo "MASTER_IP is set to: ${MASTER_IP}"
	echo "NODE_IP is set to: ${NODE_IP}"
	echo "ARCH is set to: ${ARCH}"
	echo "OS distribution is set to: ${lsb_dist}"
}

# Check if a command is valid
command_exists() {
    command -v "$@" > /dev/null 2>&1
}

# Detect the OS distro, we support ubuntu, debian, mint, centos, fedora dist
detect_lsb() {
    case "$(uname -m)" in
        *64)
            ;;
        *)
	        echo "Error: We currently only support 64-bit platforms."
	        exit 1
	        ;;
    esac

    if command_exists lsb_release; then
        lsb_dist="$(lsb_release -si)"
    fi
    if [ -z ${lsb_dist} ] && [ -r /etc/lsb-release ]; then
        lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
    fi
    if [ -z ${lsb_dist} ] && [ -r /etc/debian_version ]; then
        lsb_dist='debian'
    fi
    if [ -z ${lsb_dist} ] && [ -r /etc/fedora-release ]; then
        lsb_dist='fedora'
    fi
    if [ -z ${lsb_dist} ] && [ -r /etc/os-release ]; then
        lsb_dist="$(. /etc/os-release && echo "$ID")"
    fi

    lsb_dist="$(echo ${lsb_dist} | tr '[:upper:]' '[:lower:]')"

    case "${lsb_dist}" in
        amzn|centos|debian|ubuntu)
            ;;
        *)
            echo "Error: We currently only support ubuntu|debian|amzn|centos."
            exit 1
            ;;
    esac
}

# Start k8s components in containers
start_k8s() {
    # Make sure there is no subnet.env from previous run.
    if [[ -f ${FLANNEL_SUBNET_DIR}/subnet.env ]]; then
		rm ${FLANNEL_SUBNET_DIR}/subnet.env
    fi
	# Start flannel
    docker run \
        -d \
        --restart=${RESTART_POLICY} \
        --net=host \
        --privileged \
        -v /dev/net:/dev/net \
        -v ${FLANNEL_SUBNET_DIR}:${FLANNEL_SUBNET_DIR} \
        ${FLANNEL_IMAGE} \
        /opt/bin/flanneld \
            --ip-masq="${FLANNEL_IPMASQ}" \
            --etcd-endpoints=http://${MASTER_IP}:4001 \
            --iface="${FLANNEL_IFACE}"

	# Wait for the flannel subnet.env file to be created instead of a timeout. This is faster and more reliable
	local SECONDS=0
	while [[ ! -f ${FLANNEL_SUBNET_DIR}/subnet.env ]]; do
		if [[ ${SECONDS} == ${TIMEOUT_FOR_SERVICES} ]]; then
			echo "flannel failed to start. Exiting..."
			exit
		fi
		sleep 1
	done

    mkdir -p /var/lib/kubelet
    mount --bind /var/lib/kubelet /var/lib/kubelet
    mount --make-shared /var/lib/kubelet

    docker run \
        --name=kubelet \
        --volume=/:/rootfs:ro \
        --volume=/sys:/sys:ro \
        --volume=/var/lib/docker/:/var/lib/docker:rw \
        --volume=/var/run:/var/run:rw \
        --volume=/run:/run:rw \
        --volume=/var/lib/kubelet:/var/lib/kubelet:shared \
        --net=host \
        --pid=host \
        --privileged=true \
        --restart=${RESTART_POLICY} \
        -d \
        ${HYPERKUBE_IMAGE} \
        /hyperkube kubelet \
            --hostname-override=${NODE_IP} \
            --address="0.0.0.0" \
            --api-servers=http://${MASTER_IP}:8080 \
            --cluster-dns=10.0.0.10 \
            --cluster-domain=cluster.local \
            --allow-privileged=true --v=2  \
            --pod-infra-container-image=${PAUSE_IMAGE} \
            --network-plugin=cni \
            --network-plugin-dir=/etc/cni/net.d
}

configure_docker(){
	# Configure docker settings, then restart it
    case "${lsb_dist}" in
        amzn)
            DOCKER_CONF="/etc/sysconfig/docker"
            sed -i.bak 's/^\(MountFlags=\).*/\1shared/' $DOCKER_CONF
            service docker restart
            ;;
        centos)
            DOCKER_CONF="/usr/lib/systemd/system/docker.service"
            sed -i.bak 's/^\(MountFlags=\).*/\1shared/' ${DOCKER_CONF}
            # Add support for docker registry
            if [[ -n ${DOCKER_REGISTRY_URL} ]]; then
			  sed -i "/^ExecStart=/ s~$~ --insecure-registry=${DOCKER_REGISTRY_URL}~" ${DOCKER_CONF}
			fi
            systemctl daemon-reload
            systemctl restart docker
            ;;
        ubuntu|debian)
            if command_exists systemctl; then
              DOCKER_CONF=$(systemctl cat docker | head -1 | awk '{print $2}')
              sed -i.bak 's/^\(MountFlags=\).*/\1shared/' $DOCKER_CONF
              systemctl daemon-reload
              systemctl restart docker
            else
              DOCKER_CONF="/etc/default/docker"
              sed -i.bak 's/^\(MountFlags=\).*/\1shared/' $DOCKER_CONF
              service docker stop
              while [ `ps aux | grep /usr/bin/docker | grep -v grep | wc -l` -gt 0 ]; do
                 echo "Waiting for docker to terminate"
                 sleep 1
              done
              service docker start
            fi
            ;;
        *)
            echo "Unsupported operations system ${lsb_dist}"
            exit 1
            ;;
    esac
}

echo "Checking prerequisites & initialize variable ..."
init

echo "Set docker registry"
configure_docker

sleep 5

echo "Starting k8s ..."
start_k8s

echo "Worker done!"
