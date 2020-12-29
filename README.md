# xml-format-action

GitHub Action to formats XML files with the `xmlformat` tool.


## Design

This GitHub Action takes care of:

* Installs the `xmlformat` tool.
* Formats your XML files.
* If given, add or remove XML files from the list.

The GitHub Action **does not**:

* Commits the changed XML files automatically
* Pushes the commit automatically


## Use case: Reformatting XML files

This use case is only activated, when some XML files inside
the `xml/` paths are changed. This can be done with the
`on.push.paths` keys:


```yaml
# Add .github/workflows/reformat-xml.yml
on:
  push:
    paths:
      # Add more paths to this list:
      - "xml/*.xml"

jobs:
  reformat-xml:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Format XML
        uses: tomschr/xml-format-action@v1
        with:
           include-files: xml/*.xml
```

## Use case: Using a configuration file


```yaml
# Add .github/workflows/reformat-xml-with-config.yml

on:
  push:
    paths:
      # Add more paths to this list:
      - "xml/*.xml"

jobs:
  reformat-xml:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Format XML
        uses: tomschr/xml-format-action@v1
        with:
           include-files: xml/*.xml
           config: doc/docbook-xmlformat.conf
```

## Inputs

* `config`: Defines the config file for `xmlformat`.

* `include-files`: Includes XML files from reformatting.

* `exclude-files`: Excludes XML files from reformatting.


## Outputs

Currently, this GitHub Action does not define any outputs.


## Committing reformatted files

The GitHub Action just reformats the XML files (excluding
the exclusion list); it does not commit nor push any files.

If you want to commit and push reformatted XML files, you
have the following options:

* [actions-go/push](https://github.com/actions-go/push)
* [reformat-xml.yml](https://github.com/tomschr/xml-format-action/blob/main/.github/workflows/reformat-xml.yml)

The `reformat-xml.yml` gives an overview if you can do it
with normal git commands.