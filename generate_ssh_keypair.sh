#!/usr/bin/env bash
set -eu

green() {
  echo -e "\033[0;32m${@}\033[0m"
}

red() {
  echo -e "\033[0;31m${@}\033[0m"
}

# abort if a key pair already exists
[[ -e "bosh.pem"     ]] && red "Found key. Aborting!" && exit 1
[[ -e "bosh.pub" ]] && red "Found key. Aborting!" && exit 1

# create new key pair
ssh-keygen -t rsa -b 4096 -C "bosh" -N "" -f "bosh.pem"
mv bosh.pem.pub bosh.pub

# finally inform user about successful completion
green "Key pair created successfully."
