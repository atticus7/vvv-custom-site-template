#!/usr/bin/env bash
# Prepare Directories and Files for Provision

usage() {
  echo "Usage: $0 [ -p PROJECT_NAME ] [ -s SITE_NAME ] [ -r SITE_REPO ]"
  exit 2
}

set_variable() {
  local varname=$1
  shift
  if [ -z "${!varname}" ]; then
    eval "$varname=\"$@\""
  else
    echo "Error: $varname already set"
    usage
  fi
}


#functions go here

while getopts '?hp:s:r:' opt
do
  case $opt in
    p) set_variable PROJECT_NAME $OPTARG;;
    s) set_variable SITE_NAME $OPTARG;;
    r) set_variable SITE_REPO $OPTARG;;
    h|?) usage;;
    \?) echo "Invalid option"
  esac
done

echo " * Creating Directories..."
mkdir -p "~/vvv/${PROJECT_NAME}/vvv-local/www/${SITE_NAME}"
mkdir-p  "~/vvv/${PROJECT_NAME}/vvv-local/www/tmp"
echo " * Cloning Site Repo to tmp..."
git clone "https://github.com/${SITE_REPO}.git" "~/vvv/${PROJECT_NAME}/vvv-local/www/tmp"
cd "~/vvv/${PROJECT_NAME}/vvv-local/www/tmp"
git checkout dev
echo " * "
cp "~/vvv/${PROJECT_NAME}/vvv-local/www/tmp/vvv/config.yml" "~/vvv/${PROJECT_NAME}/vvv-local/config/config.yml"
