declare -A release_catalog_map

# This map is used to determine the catalog version based on the release branch
release_catalog_map["release-4.20"]="v10.20"
release_catalog_map["release-4.19"]="v10.19"
release_catalog_map["release-4.18"]="v10.18"
release_catalog_map["release-4.17"]="v10.17"
release_catalog_map["release-4.16"]="v10.16"
release_catalog_map["release-4.15"]="v10.15"
release_catalog_map["release-4.14"]="v9"
release_catalog_map["release-4.13"]="v8"
release_catalog_map["release-4.12"]="v7"

# This function retrieves the catalog version based on the target branch
# The the catalog version must correspond to the name of the directory containing the catalog-template.json file
get_catalog() {
  local target_branch="$1"
  if [[ -v release_catalog_map[$target_branch] ]]; then
    catalog="${release_catalog_map[$target_branch]}"
  else
    echo "Error: '$target_branch' is not a valid key in release_catalog_map" >&2
    return 1
  fi
  echo "${catalog}"
}
