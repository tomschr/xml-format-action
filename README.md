# xml-format-action v1

GitHub Action to formats all XML files of the current commit with the `xmlformat` tool.


## Design

This GitHub Action takes care of:

* Installs the `xmlformat-ruby` package.
* Finds the `xmlformat` script. For some distributions, it is
  available as `xmlformat`, `xmlformat.rb` or `xmlformat.pl`.
  It will find the script in the mentioned order.
* Investigates what files are integrated in the commit.
* Optionally, lets you set a configuration file. If it's a remote address,
  it will download the config file automatically.
* Optionally, define a list of excluded files.
* Optionally, lets you define a list of allowed file extensions.
* Optionally, lets you commit the changed XML files.

The GitHub Action **does not** push the changed XML files automatically. You have to do it after you have formatted
the files (see [Pushing reformatted XML files](#pushing).)


## Prerequisites


### Action Requirements

This GitHub Action consists of [composite run steps](https://docs.github.com/en/free-pro-team@latest/actions/creating-actions/creating-a-composite-run-steps-action).
Used commands are:

* `bash`
* `curl`
* `git`
* `jq`
* `xmlformat`

Except for `xmlformat`, all commands are already available
in the default image (Ubuntu).
If you use any other image, make sure to have these commands available.


### Job Requirements

This GH Action is only useful for real commits, not tags. As such,
it is needed to skip any runs when you've created tags. Use these
lines:

```yaml
jobs:
  reformat-xml:
    # True for any branches, but is skipped for tags
    # For tags it would be 'refs/tags/'
    if: startsWith(github.ref, 'refs/heads/')
```

### Step Requirements

To avoid shallow copies of your checkout, you need to get *all*
commits from your history.
When checking out your repository with `actions/checkout`,
use the option `fetch-depth` and set it to zero:

```yaml
- uses: actions/checkout@v2
  with:
    # Number of commits to fetch.
    # 0 indicates all history for all branches and tags.
    # This is absolutely needed for this action,
    # otherwise it won't work!
    fetch-depth: 0
```

**Important: If you forget that, the `xml-format-action` won't find any files at all!**


Another recommendation (although it's not a requirement) is to use the
`on.push.paths` key.
This key could be helpful if you are only interested to enable this
action for specific paths or files:

```yaml
---
on:
  push:
    paths:
      # Only active this GH Action when these files are changed:
      - "a/*.xml"
      - "b/*.xml"
```

## Inputs

Name             | Required? | Type     | Default | Explanation
-----------------|----------|-----------|---------|-----------------------------------------
`commit`         | no       | bool<sup id="bool">[1](#f1)</sup>     | true    | flag: should the formatted files committed?
`commit-message` | no       | string   | "..."   | commit message for the reformatting step
`config`         | no       | file/URL | n/a     | config file for the `xmlformat` script
`extensions`     | no       | string/ML<sup id="ML">[2](#f2)</sup>   | `xml`   | file extensions for XML files (without dots or globs)
`exclude-files`  | no       | string/ML<sup id="ML">[2](#f2)</sup>   | n/a     | Excluded XML files from reformatting
`repo-token`     | yes      | string   | n/a     | The GitHub token, usually `secrets.GITHUB_TOKEN`. Needed to access the repo.

[<a name="f1">[1](#bool)</a>]: boolean value, use `true` (also
allowed is `1` or `yes`).

[<a name="f2">[2](#ML)</a>]: multi line input with the pipe symbol (`|`)
or as a string. Each part is separated by one or more spaces.



## Outputs

Name            | Type | Explanation
----------------|------|-----------------
`xmlfound`      | bool | Does the commit contains some XML files and were they reformatted?

## Use case: Reformatting XML files

This workflow is only activated, when some XML files inside
the `xml/` and the root paths have been changed (using the
`on.push.paths` key):


```yaml
# Add .github/workflows/reformat-xml.yml
on:
  push:
    paths:
      - "xml/*.xml"
      - "*.xml"

jobs:
  reformat-xml:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v2
        with:
           # Number of commits to fetch. See above.
           fetch-depth: 0

      - name: Format XML
        uses: tomschr/xml-format-action@v1
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}
```

## Use case: Using a configuration file

In most cases, the default formatting is not what you want.
If you already have a configuration file (either in your
current repository or somewhere else) you can provide this.
Use the `config` input:

```yaml
# Add .github/workflows/reformat-xml-config.yml

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
        with:
           fetch-depth: 0

      - name: Format XML
        uses: tomschr/xml-format-action@v1
        with:
           repo-token: ${{ secrets.GITHUB_TOKEN }}
           config: doc/docbook-xmlformat.conf
```

It's also possible to use a URL for the config file.
For example:

```yaml
- name: Format XML from remote URL
    uses: tomschr/xml-format-action@v1
    with:
      repo-token: ${{ secrets.GITHUB_TOKEN }}
      config: https://github.com/openSUSE/daps/raw/main/etc/docbook-xmlformat.conf
```

In this case, the remote config file is downloaded and saved
outside the checked out repository (in the `/tmp` directory).


## Use case: Excluding XML files from reformatting

Sometimes you have configuration files which happen to end
with the same file extension (Emacs has `schemas.xml`). If
you want to exclude such files from reformatting, use the
key `exclude-files`:

```yaml
# Add .github/workflows/reformat-xml-exclude-files.yml

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
           repo-token: ${{ secrets.GITHUB_TOKEN }}
           exclude-files: "xml/schemas.xml"
```

If you want to exclude more than one file, use the pipe (`|`)
symbol:

```yaml
- name: Format XML
  uses: tomschr/xml-format-action@v1
  with:
    exclude-files: |
      xml/foo.xml
      xml/bar.xml
```

## Use case: Including XML files with different extensions

In some cases you have your XML files which does not end up with `.xml`.
For example, SVG (`.svg`) or MathML (`.mml`) files.
Use the `extensions` key to add them:

```yaml
# Add .github/workflows/reformat-xml-extensions.yml

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
           repo-token: ${{ secrets.GITHUB_TOKEN }}
           extensions: "mml"
```

You can also use the pipe (`|`) symbol to add more than
one file extension:

```yaml
- name: Format XML
  uses: tomschr/xml-format-action@v1
  with:
    extension: |
      xml
      svg
      mml
```


## Use case: Providing a different commit message

If you prefer a different commit message, use the key `commit-message`:

```yaml
# Add .github/workflows/reformat-xml-extensions.yml

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
           repo-token: ${{ secrets.GITHUB_TOKEN }}
           commit-message: "Reformatted by xml-format-action"
```


## Use case: Debugging

If something goes wrong, you can introduce the following step into your workflow:

```yaml
- name: Dump GitHub Context
  env:
    GITHUB_CONTEXT: ${{ toJson(github) }}
  run: echo "${GITHUB_CONTEXT}"
```

This converts the GitHub context into JSON and outputs it in your action.


## <a name="pushing"></a>Pushing reformatted XML files

The GitHub Action reformats the XML files (excluding
the exclusion list) and commits them. However, it does not push any files.

If you want to push reformatted XML files to your GitHub
repository, use the [actions-go/push](https://github.com/actions-go/push) action.
Or, if you want to do it manually, use these steps in your workflow file:

```yaml
- name: Format DocBook XML
    id: dbxml
    uses: tomschr/xml-format-action@v1
    with:
      repo-token: ${{ secrets.GITHUB_TOKEN }}
      # use whatever you need

  - name: Push
    if: ${{ steps.dbxml.outputs.xmlfound }}
    run: |
        # Remove any refs/heads/ parts:
        BRANCH="${GITHUB_REF#refs/heads/}"
        URL="https://${{github.actor}}:${{secrets.SOURCE_PUSH_TOKEN}}@github.com/${{github.repository}}.git"
        git push "$URL" "$BRANCH"
```

As pushing to an existing repo needs read/write permissions, using `secrets.GITHUB_TOKEN`
[is not enough](https://docs.github.com/en/free-pro-team@latest/actions/reference/authentication-in-a-workflow#permissions-for-the-github_token) as it contains only read access.
That's why the push step uses the token named `SOURCE_PUSH_TOKEN`.

To create such token with read/write permissions, refer to the section
[Creating encrypted secrets for a repository](https://docs.github.com/en/free-pro-team@latest/actions/reference/encrypted-secrets#creating-encrypted-secrets-for-a-repository) of the GitHub documentation.

The push step only pushes files if the previous step (`Format DocBook XML` with `id=dbxml`) contained
files which are detected as XML and where changed.
