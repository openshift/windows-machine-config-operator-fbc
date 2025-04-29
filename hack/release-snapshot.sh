#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# This script automates the process of updating the `olm.bundle` image in the catalog template, rendering the catalog
# JSON file, and creating a new branch with the changes.
#
# Usage:
#   ./hack/release-snapshot.sh [TARGET_BRANCH] [COMMIT_SHA]
#
# Parameters:
# - TARGET_BRANCH (optional): The target branch for the release. Defaults to `master` if not provided.
# - COMMIT_SHA (optional): The specific commit SHA to use for the snapshot. Defaults to `latest` if not provided.
#
# Prerequisites:
# - Ensure you have the `oc` CLI installed and configured with rhtap-releng tenant
# - Ensure the `jq` and `opm` tools are installed and available in your PATH.
# - Ensure registry.stage.redhat.io is configured in your local config.
#
# Example:
# ./hack/release-snapshot.sh release-4.19 47c0910ba865dd0821cf76824e6086a90aa32de8
#
# This will:
# 1. Switch to the `windows-machine-conf-tenant` project in rhtap-releng.
# 2. Use the `release-4.19` branch and the commit SHA `47c0910` to find the snapshot.
# 3. Update the `olm.bundle` image in the catalog template.
# 4. Render the catalog JSON file.
# 5. Create a new branch named `release-release-4.19-47c0910` with the changes and push it to the repository.

# import the release catalog map script
source hack/release_catalog_map.sh

# check tenant project
oc project windows-machine-conf-tenant || {
  echo "Error: Failed to switch to the windows-machine-conf-tenant project"
  echo "Ensure KUBECONFIG points to correct rhtap-releng tenant"
  exit 1
}

# use the first argument as the target branch, or default to master
TARGET_BRANCH="${1:-master}"

# get the catalog version based on the target branch
CATALOG_TEMPLATE_PATH=$(get_catalog "${TARGET_BRANCH}")
echo ""
echo "Catalog template: ${CATALOG_TEMPLATE_PATH}/catalog-template.json"
# read the catalog template file and extract the image value for olm.bundle
IMAGE_VALUE=$(jq -r 'last(.entries[] | select(.schema == "olm.bundle")) | .image' "${CATALOG_TEMPLATE_PATH}/catalog-template.json")
if [[ "${IMAGE_VALUE}" == "null" ]]; then
  echo "Error: cannot find olm.bundle image entry in ${CATALOG_TEMPLATE_PATH}/catalog-template.json"
  exit 1
fi
if [[ -z "${IMAGE_VALUE}" ]]; then
  echo "Error: olm.bundle image cannot be empty in ${CATALOG_TEMPLATE_PATH}/catalog-template.json"
  exit 1
fi
echo "Catalog template last olm.bundle image: ${IMAGE_VALUE}"

# replace dots with dashes in the target branch name to create the name
ORIGINAL_PRNAME="windows-machine-config-operator-bundle-${TARGET_BRANCH//./-}-on-push"
echo ""
echo "Snapshot name: ${ORIGINAL_PRNAME}"

# set the label filter to match the name
LABEL_FILTER="pac.test.appstudio.openshift.io/original-prname=${ORIGINAL_PRNAME}"

# check commit sha, or default to latest
COMMIT_SHA="${2:-latest}"
if [[ "${COMMIT_SHA}" != "latest" ]]; then
  # if a commit sha is provided, add it to the label filter
  LABEL_FILTER="${LABEL_FILTER},pac.test.appstudio.openshift.io/sha=${COMMIT_SHA}"
fi

# get the first snapshot based on the filter
SNAPSHOT_JSON=$(oc get snapshots -l "${LABEL_FILTER}" \
   --sort-by=.metadata.creationTimestamp \
   -o jsonpath='{.items[-1]}' ) || {
         echo "Error: No snapshot found matching the specified label filter: ${LABEL_FILTER}"
         exit 1
}

if [[ -z "${SNAPSHOT_JSON}" ]]; then
  echo "Error: Finding snapshot for label filter: ${LABEL_FILTER}"
  exit 1
fi

COMMIT_SHA_TITLE=$(echo "${SNAPSHOT_JSON}" | jq -r '.metadata.annotations["pac.test.appstudio.openshift.io/sha-title"]')
echo "Snapshot commit title: ${COMMIT_SHA_TITLE}"

COMMIT_SHA=$(echo "${SNAPSHOT_JSON}" | jq -r '.metadata.annotations["build.appstudio.redhat.com/commit_sha"]')
echo "Snapshot commit sha: ${COMMIT_SHA}"

COMPONENT_NAME="windows-machine-config-operator-${TARGET_BRANCH//./-}"
OPERATOR_CONTAINER_COMMIT_SHA=$(echo "${SNAPSHOT_JSON}" | jq -r --arg componentName "$COMPONENT_NAME" '.spec.components[] | select(.name == $componentName) | .source.git.revision')
if [[ -z "${OPERATOR_CONTAINER_COMMIT_SHA}" ]]; then
  echo "Error: cannot find source revision for component: ${COMPONENT_NAME}"
  exit 1
fi
if [[ "${COMMIT_SHA}" != "${OPERATOR_CONTAINER_COMMIT_SHA}" ]]; then
  echo ""
  echo "Warning: commit sha does not match with operator source revision: ${OPERATOR_CONTAINER_COMMIT_SHA}"
  OPERATOR_CONTAINER_IMAGE=$(echo "${SNAPSHOT_JSON}" | jq -r --arg componentName "$COMPONENT_NAME" '.spec.components[] | select(.name == $componentName) | .containerImage')
  echo "Snapshot operator container image: ${OPERATOR_CONTAINER_IMAGE}"
  echo ""
fi

COMPONENT_NAME="windows-machine-config-operator-bundle-${TARGET_BRANCH//./-}"
BUNDLE_CONTAINER_IMAGE=$(echo "${SNAPSHOT_JSON}" | jq -r --arg componentName "$COMPONENT_NAME" '.spec.components[] | select(.name == $componentName) | .containerImage')
if [[ -z "${BUNDLE_CONTAINER_IMAGE}" ]]; then
  echo "Error: cannot find containerImage for component: ${COMPONENT_NAME}"
  exit 1
fi
echo "Snapshot bundle container image: ${BUNDLE_CONTAINER_IMAGE}"

# extract the tag from the bundle container image
BUNDLE_CONTAINER_IMAGE_HASH="${BUNDLE_CONTAINER_IMAGE#*@sha256:}"
echo "Snapshot bundle container image hash: ${BUNDLE_CONTAINER_IMAGE_HASH}"

# extract the registry and repository from the current image value
IMAGE_VALUE="${IMAGE_VALUE%@sha256:*}"

# update the image with the new bundle container image
IMAGE_VALUE="${IMAGE_VALUE}@sha256:${BUNDLE_CONTAINER_IMAGE_HASH}"

# replace the SHA in the catalog template
jq --indent 4 --arg image_value "$IMAGE_VALUE" '.entries[-1].image = $image_value' \
  "${CATALOG_TEMPLATE_PATH}/catalog-template.json" > tmp.json && \
  mv tmp.json "${CATALOG_TEMPLATE_PATH}/catalog-template.json"

# read file and print the updated image value
jq -r '.entries[-1].image' "${CATALOG_TEMPLATE_PATH}/catalog-template.json"
echo "Updated olm.bundle image hash in ${CATALOG_TEMPLATE_PATH}/catalog-template.json"

# default migrate level to none
MIGRATE_LEVEL="none"
if [[ "${TARGET_BRANCH}" == "master"  || "${TARGET_BRANCH}" > "release-4.16" ]]; then
  # Adjust migrate level for OCP 4.17 and later
  # See https://github.com/konflux-ci/olm-operator-konflux-sample/blob/main/docs/konflux-onboarding.md#create-the-fbc-in-the-git-repository
  MIGRATE_LEVEL="bundle-object-to-csv-metadata"
fi

echo "Rendering catalog template for ${CATALOG_TEMPLATE_PATH} with migrate level ${MIGRATE_LEVEL}"
opm alpha render-template \
  basic "${CATALOG_TEMPLATE_PATH}/catalog-template.json" \
  --migrate-level="${MIGRATE_LEVEL}" > "${CATALOG_TEMPLATE_PATH}/catalog/windows-machine-config-operator/catalog.json" || {
    echo "Error: Failed to render template. Check the ec job passed for the given commit hash ${COMMIT_SHA}"
    exit 1
  }

# create a new branch, commit and push the changes
WMCO_COMMIT_URL="https://github.com/openshift/windows-machine-config-operator/commit/"
SHORT_COMMIT_SHA="${COMMIT_SHA:0:7}"
BRANCH_NAME="release-${TARGET_BRANCH}-${SHORT_COMMIT_SHA}"
git checkout -b "${BRANCH_NAME}"
git add "${CATALOG_TEMPLATE_PATH}/"
git commit -m "${TARGET_BRANCH}: release ${SHORT_COMMIT_SHA}" \
  -m "Updates ${CATALOG_TEMPLATE_PATH} olm.bundle image to ${WMCO_COMMIT_URL}${COMMIT_SHA}" \
  -m "This commit was generated using hack/release_snapshot.sh"

echo ""
echo ""
echo "Run the following command to push the changes:"
echo "    git push origin ${BRANCH_NAME}"
echo ""

exit 0
