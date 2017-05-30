#!/bin/bash

#
# Webintrinsics Clusterlite - Simpler alternative to Kubernetes and Docker Swarm
# License: https://github.com/webintrinsics/clusterlite/blob/master/LICENSE
#
# Prerequisites:
# - Ubuntu 16.04 machine (or another Linux with installed docker 1.13.1)
#   with valid hostname, IP interface, DNS, proxy, apt-get configuration
# - Internet connection
#

set -e

log="[clusterlite]"

#
# install docker if it does not exist
#
if [[ $(which docker) == "" ]];
then
    if [ $(uname -a | grep Ubuntu | wc -l) == 1 ]
    then
        # ubuntu supports automated installation
        (>&2 echo "$log installing docker")
        apt-get -y update || (>&2 echo "apt-get update failed, are proxy settings correct?" && exit 1)
        apt-get -qq -y install --no-install-recommends curl
    else
        (>&2 echo "failure: docker has not been found, please install docker and run docker daemon")
        exit 1
    fi

    # Run the installation script to get the latest docker version.
    # This is disabled in favor of controlled migration to latest docker versions
    # curl -sSL https://get.docker.com/ | sh

    # Use specific version for installation
    apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    mkdir -p /etc/apt/sources.list.d || echo ""
    echo deb https://apt.dockerproject.org/repo ubuntu-xenial main > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get -qq -y install --no-install-recommends docker-engine=1.13.1-0~ubuntu-xenial

    # Configure and start Engine
    dockerd daemon -H unix:///var/run/docker.sock

    # Verify that Docker Engine is installed correctly:
    docker run hello-world
fi

if [[ $(docker --version) != "Docker version 1.13.1, build 092cba3" ]];
then
    (>&2 echo "failure: required docker version 1.13.1")
    exit 1
fi

#
# Prepare the environment and command
#
(>&2 echo "$log preparing the environment")
export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export HOSTNAME=$(hostname -f)
export HOSTNAME_I=$(hostname -i | awk {'print $1'})
export CLUSTERLITE_ID=$(date +%Y%m%d-%H%M%S.%N-%Z)

# capture docker state
(>&2 echo "$log capturing docker state")
docker_ps=$(docker ps | grep -v CONTAINER | awk '{print $1}')
if [[ ${docker_ps} == "" ]];
then
    docker_inspect="[]"
else
    docker_inspect=$(docker inspect ${docker_ps} || echo "[]")
fi

# capture weave state
(>&2 echo "$log capturing weave state")
if [[ $(which weave) == "" || $(docker ps | grep weaveexec | wc -l) == "0" ]];
then
    weave_inspect="{}"
else
    weave_inspect=$(weave report || echo "{}")
fi

# capture clusterlite state
(>&2 echo "$log capturing clusterlite state")
if [[ -f "/var/lib/clusterlite/volume.txt" ]];
then
    volume=$(cat /var/lib/clusterlite/volume.txt)
else
    volume=""
fi
if [[ ${volume} == "" ]];
then
    clusterlite_json="{}"
    placements_json="{}"
    clusterlite_data="/tmp/${CLUSTERLITE_ID}"
else
    clusterlite_json=$(cat ${volume}/clusterlite.json || echo "{}")
    placements_json=$(cat ${volume}/placements.json || echo "{}")
    clusterlite_data="${volume}/clusterlite/${CLUSTERLITE_ID}"
fi

# prepare working directory for an action
(>&2 echo "$log preparing working directory")
mkdir ${clusterlite_data}
echo ${docker_inspect} > ${clusterlite_data}/docker.json
echo ${weave_inspect} > ${clusterlite_data}/weave.json
echo ${clusterlite_json} > ${clusterlite_data}/clusterlite.json
echo ${placements_json} > ${clusterlite_data}/placements.json

#
# prepare execution command
#
(>&2 echo "$log preparing execution command")
package_dir=${SCRIPT_DIR}/target/universal
package_path=${package_dir}/clusterlite-0.1.0.zip
package_md5=${package_dir}/clusterlite.md5
package_unpacked=${package_dir}/clusterlite
if [ -z ${package_path} ];
then
    # production mode
    command="docker run -ti \
    --env HOSTNAME=$HOSTNAME \
    --env HOSTNAME_I=$HOSTNAME_I \
    --env CLUSTERLITE_ID=$CLUSTERLITE_ID \
    --volume ${volume}/clusterlite:/data \
    webintrinsics/clusterlite:0.1.0 /opt/clusterlite/bin/clusterlite $@"
else
    # development mode
    export CLUSTERLITE_DATA=${clusterlite_data}
    md5_current=$(md5sum ${package_path} | awk '{print $1}')
    if [ ! -f ${package_md5} ] || [[ ${md5_current} != $(cat ${package_md5}) ]] || [ ! -d ${package_unpacked} ]
    then
        unzip -o ${package_path} -d ${package_dir} 1>&2
        echo ${md5_current} > ${package_md5}
    fi
    command="${package_unpacked}/bin/clusterlite $@"
fi

#
# execute the command, capture the output and execute the output
#
(>&2 echo "$log executing ${command}")
tmpscript=${clusterlite_data}/output
execute_output() {
    (>&2 echo "$log saving ${tmpscript}")
    first_line=$(cat ${tmpscript} | head -1)
    tr -d '\015' <${tmpscript} >${tmpscript}.sh # dos2unix if needed
    if [[ ${first_line} == "#!/bin/bash" ]];
    then
        chmod u+x ${tmpscript}.sh
        ${tmpscript}.sh || (>&2 echo "$log failure: internal error, please report to https://github.com/webintrinsics/clusterlite" && exit 1)
    else
        cat ${tmpscript}.sh
    fi
    if [[ -f ${tmpscript}.sh ]];
    then
        # can be deleted as a part of uninstall action
        rm ${tmpscript}.sh
    fi
}
${command} > ${tmpscript} 2>&1 || (execute_output && exit 1)
if [ -z ${tmpscript} ];
then
    (>&2 echo "$log exception: file ${tmpscript} has not been created")
    (>&2 echo "$log failure: internal error, please report to https://github.com/webintrinsics/clusterlite")
    exit 1
fi
execute_output
(>&2 echo "$log success: action completed")
