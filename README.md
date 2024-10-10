## Adding a new stream

```
# Adding 4.17 as an example
# Copy an existing directory
cp -r windows-machine-config-operator/release-4.15/ windows-machine-config-operator/release-4.17

# Replace references to old OCP version with new
...

# Pull Red Hat operators catalog for the given OCP version
opm migrate registry.redhat.io/redhat/redhat-operator-index:v4.17 ./catalog-migrate

# Copy the WMCO catalog
cp catalog-migrate/windows-machine-config-operator/catalog.json windows-machine-config-operator/release-4.17/catalog/catalog.json

```

