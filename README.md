# Windows Machine Config Operator FBC

FBC for the [Windows Machine Config Operator](https://github.com/openshift/windows-machine-config-operator)

The [olm-sample](https://github.com/konflux-ci/olm-operator-konflux-sample/blob/main/docs/konflux-onboarding.md) should be used as a source of truth, over the information here.

## Adding a release stream

### Adding a new release stream

```
# Copy an existing directory
cp -r windows-machine-config-operator/release-4.15/ windows-machine-config-operator/new-stream

# Replace references to old OCP version with new
...

# Generate catalog using a recent bundle build
opm render quay.io/redhat-user-workloads/windows-machine-conf-tenant/windows-machine-config-operator/windows-machine-config-operator-bundle-<$release>@<$DIGEST> --migrate-level=bundle-object-to-csv-metadata >catalog.json
# Convert the catalog to a basic template
opm alpha convert-template basic catalog.json >catalog-template.json

# Ensure all references in catalog.json point to the same registry.
# This should be registry.redhat.io for most streams and registry.stage.redhat.io for the stream tracked by the WMCO master branch
# Both the catalog and the template should be committed to git
```

### Adding a release stream from an older catalog source (migrating to konflux)

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
# Convert the catalog to a basic template
opm alpha convert-template basic catalog.json >catalog-template.json

# Both the catalog and the template should be committed to source
```

## Updating a patch version before release

```
# Update the bundle digest in the catalog-template for the stream with your editor of choice.
nvim v10.19/catalog-template.json

# Generate a new catalog
opm alpha render-template basic v10.19/catalog-template.json --migrate-level=bundle-object-to-csv-metadata  > v10.19/catalog/windows-machine-config-operator/catalog.json; 

# Ensure all references in catalog.json point to the same registry.
# This should be registry.redhat.io for most streams and registry.stage.redhat.io for the stream tracked by the WMCO master branch
```
