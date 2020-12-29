# xml-format-action

GitHub Action to formats XML files with the `xmlformat` tool.


## Design

This GitHub Action takes care of:

* Installs the `xmlformat-ruby` package.
* Formats your XML files.
* Optionally lets you set a configuration file.
* Optionally, define a list of excluding files.

The GitHub Action **does not**:

* Commits the changed XML files automatically
* Pushes the commit automatically


## Use case: Reformatting XML files

This use case is only activated, when some XML files inside
the `xml/` and the root paths have been changed.
This can be done with the `on.push.paths` keys:


```yaml
# Add .github/workflows/reformat-xml.yml
on:
  push:
    paths:
      # Add more paths to this list:
      - "xml/*.xml"
      - "*.xml"

jobs:
  reformat-xml:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2

      - name: Format XML
        uses: tomschr/xml-format-action@v1
```

## Use case: Using a configuration file

In some cases, the default formatting is not what you want.
In this case, you can provide a configuration file. Use
the key `config`:

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

It's also possible to use a URL for the config file.
For example:

```yaml
- name: Format XML from remote URL
    uses: tomschr/xml-format-action@v1
    with:
        config: https://github.com/openSUSE/daps/raw/main/etc/docbook-xmlformat.conf
```

In this case, the remote config file is downloaded and saved
in the `/tmp` directory.


## Use case: Excluding XML files from reformatting

Sometimes you have configuration files which happen to end
with the same file extension (Emacs has `schemas.xml`). If
you want to exclude such files from reformatting, use the
key `exclude-files`:

```yaml
# Add .github/workflows/reformat-exclude-files.yml

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
           exclude-files: xml/schemas.xml
```

## Use case: Including XML files from different paths

In some cases you have your XML files in different directories.
Use the `include-files` key to add them:

```yaml
# Add .github/workflows/reformat-xml-two-paths.yml

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
           include-files: "folder1/*.xml folder2/*.xml"
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