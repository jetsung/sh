#!/usr/bin/env bash

sh_dir=$(mktemp -d /tmp/sh.XXX)
git clone -b dev https://framagit.org/jetsung/sh.git "${sh_dir}"

pushd "${sh_dir}/install" > /dev/null || exit
    bash nginx.sh
popd > /dev/null || exit
