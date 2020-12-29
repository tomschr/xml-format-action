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
           config: doc/docbook-xmlformat.conf
```