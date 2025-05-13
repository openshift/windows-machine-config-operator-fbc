set -e
for dir in v*/; do
  catalog="${dir}catalog/windows-machine-config-operator/catalog.json"
  images=$(cat $catalog | jq '. | select(.schema=="olm.bundle")| .relatedImages[].image')
  registries=$(echo "$images" | cut -f1 -d"/"| uniq)
  if [ $(echo "$registries" | wc -l) -ne 1 ];then
    echo "error: multiple registries found in $catalog"
    echo "please ensure the bundle and operator images are coming from the same registry"
    echo "found registries:"
    echo "$registries"
    exit 1
  fi
done
echo no issues found
