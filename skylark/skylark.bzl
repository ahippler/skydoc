# Copyright 2016 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Skylark rules"""

_SKYLARK_FILETYPE = FileType([".bzl"])

ZIP_PATH = "/usr/bin/zip"

def _get_transitive_sources(deps):
  """Collects source files of transitive dependencies."

  Args:
    deps: List of deps labels from ctx.attr.deps.

  Returns:
    Returns a list of Files containing sources of transitive dependencies.
  """
  transitive_sources = depset(order="postorder")
  for dep in deps:
    transitive_sources += dep.transitive_bzl_files
  return transitive_sources

def _skylark_library_impl(ctx):
  """Implementation of the skylark_library rule."""
  sources = _get_transitive_sources(ctx.attr.deps) + ctx.files.srcs
  return struct(files = depset(),
                transitive_bzl_files = sources)

def _skydoc(ctx):
  for f in ctx.files.skydoc:
    if not f.path.endswith(".py"):
      return f

def _skylark_doc_impl(ctx):
  """Implementation of the skylark_doc rule."""
  skylark_doc_zip = ctx.outputs.skylark_doc_zip
  inputs = _get_transitive_sources(ctx.attr.deps) + ctx.files.srcs
  sources = [source.path for source in inputs]
  flags = [
      "--format=%s" % ctx.attr.format,
      "--output_file=%s" % ctx.outputs.skylark_doc_zip.path,
  ]
  if ctx.attr.strip_prefix:
    flags += ["--strip_prefix=%s" % ctx.attr.strip_prefix]
  if ctx.attr.overview:
    flags += ["--overview"]
  if ctx.attr.overview_filename:
    flags += ["--overview_filename=%s" % ctx.attr.overview_filename]
  if ctx.attr.link_ext:
    flags += ["--link_ext=%s" % ctx.attr.link_ext]
  if ctx.attr.site_root:
    flags += ["--site_root=%s" % ctx.attr.site_root]
  skydoc = _skydoc(ctx)
  ctx.action(
      inputs = list(inputs) + [skydoc],
      executable = skydoc,
      arguments = flags + sources,
      outputs = [skylark_doc_zip],
      mnemonic = "Skydoc",
      use_default_shell_env = True,
      progress_message = ("Generating Skylark doc for %s (%d files)"
                          % (ctx.label.name, len(sources))))

_skylark_common_attrs = {
    "srcs": attr.label_list(allow_files = _SKYLARK_FILETYPE),
    "deps": attr.label_list(providers = ["transitive_bzl_files"],
                            allow_files = False),
}

skylark_library = rule(
    _skylark_library_impl,
    attrs = _skylark_common_attrs,
)
"""Creates a logical collection of Skylark .bzl files.

Args:
  srcs: List of `.bzl` files that are processed to create this target.
  deps: List of other `skylark_library` targets that are required by the Skylark
    files listed in `srcs`.

Example:
  If you would like to generate documentation for multiple .bzl files in various
  packages in your workspace, you can use the `skylark_library` rule to create
  logical collections of Skylark sources and add a single `skylark_doc` target for
  building documentation for all of the rule sets.

  Suppose your project has the following structure:

  ```
  [workspace]/
      WORKSPACE
      BUILD
      checkstyle/
          BUILD
          checkstyle.bzl
      lua/
          BUILD
          lua.bzl
          luarocks.bzl
  ```

  In this case, you can have `skylark_library` targets in `checkstyle/BUILD` and
  `lua/BUILD`:

  `checkstyle/BUILD`:

  ```python
  load("@io_bazel_skydoc//skylark:skylark.bzl", "skylark_library")

  skylark_library(
      name = "checkstyle-rules",
      srcs = ["checkstyle.bzl"],
  )
  ```

  `lua/BUILD`:

  ```python
  load("@io_bazel_skydoc//skylark:skylark.bzl", "skylark_library")

  skylark_library(
      name = "lua-rules",
      srcs = [
          "lua.bzl",
          "luarocks.bzl",
      ],
  )
  ```

  To build documentation for all the above `.bzl` files at once:

  `BUILD`:

  ```python
  load("@io_bazel_skydoc//skylark:skylark.bzl", "skylark_doc")

  skylark_doc(
      name = "docs",
      deps = [
          "//checkstyle:checkstyle-rules",
          "//lua:lua-rules",
      ],
  )
  ```

  Running `bazel build //:docs` would build a single zip containing documentation
  for all the `.bzl` files contained in the two `skylark_library` targets.
"""

_skylark_doc_attrs = {
    "format": attr.string(default = "markdown"),
    "strip_prefix": attr.string(),
    "overview": attr.bool(default = True),
    "overview_filename": attr.string(),
    "link_ext": attr.string(),
    "site_root": attr.string(),
    "skydoc": attr.label(
        default = Label("//skydoc"),
        cfg = "host",
        executable = True),
}

skylark_doc = rule(
    _skylark_doc_impl,
    attrs = dict(_skylark_common_attrs.items() + _skylark_doc_attrs.items()),
    outputs = {
        "skylark_doc_zip": "%{name}-skydoc.zip",
    },
)
"""Generates Skylark rule documentation.

Documentation is generated in directories that follows the package structure
of the input `.bzl` files. For example, suppose the set of input files are
as follows:

* `foo/foo.bzl`
* `foo/bar/bar.bzl`

The archive generated by `skylark_doc` will contain the following generated
docs:

* `foo/foo.html`
* `foo/bar/bar.html`

Args:
  srcs: List of `.bzl` files that are processed to create this target.
  deps: List of other `skylark_library` targets that are required by the Skylark
    files listed in `srcs`.
  format: The type of output to generate. Possible values are `"markdown"` and
    `"html"`.
  strip_prefix: The directory prefix to strip from the generated output files.

    The directory prefix to strip must be common to all input files. Otherwise,
    skydoc will raise an error.
  overview: If set to `True`, then generate an overview page.
  overview_filename: The file name to use for the overview page. By default,
    the page is named `index.md` or `index.html` for Markdown and HTML output
    respectively.
  link_ext: The file extension used for links in the generated documentation.
    By default, skydoc uses `.html`.
  site_root: The site root to be prepended to all URLs in the generated
    documentation, such as links, style sheets, and images.

    This is useful if the generated documentation is served from a subdirectory
    on the web server. For example, if the skydoc site is to served from
    `https://host.com/rules`, then by setting
    `site_root = "https://host.com/rules"`, all links will be prefixed with
    the site root, for example, `https://host.com/rules/index.html`.

Outputs:
  skylark_doc_zip: A zip file containing the generated documentation.

Example:
  Suppose you have a project containing Skylark rules you want to document:

  ```
  [workspace]/
      WORKSPACE
      checkstyle/
          BUILD
          checkstyle.bzl
  ```

  To generate documentation for the rules and macros in `checkstyle.bzl`, add the
  following target to `rules/BUILD`:

  ```python
  load("@io_bazel_skydoc//skylark:skylark.bzl", "skylark_doc")

  skylark_doc(
      name = "checkstyle-docs",
      srcs = ["checkstyle.bzl"],
  )
  ```

  Running `bazel build //checkstyle:checkstyle-docs` will generate a zip file
  containing documentation for the public rules and macros in `checkstyle.bzl`.

  By default, Skydoc will generate documentation in Markdown. To generate
  a set of HTML pages that is ready to be served, set `format = "html"`.
"""

JINJA2_BUILD_FILE = """
py_library(
    name = "jinja2",
    srcs = glob(["jinja2/*.py"]),
    srcs_version = "PY2AND3",
    deps = [
        "@markupsafe_archive//:markupsafe",
    ],
    visibility = ["//visibility:public"],
)
"""

MARKUPSAFE_BUILD_FILE = """
py_library(
    name = "markupsafe",
    srcs = glob(["markupsafe/*.py"]),
    srcs_version = "PY2AND3",
    visibility = ["//visibility:public"],
)
"""

MISTUNE_BUILD_FILE = """
py_library(
    name = "mistune",
    srcs = ["mistune.py"],
    srcs_version = "PY2AND3",
    visibility = ["//visibility:public"],
)
"""

SIX_BUILD_FILE = """
py_library(
    name = "six",
    srcs = ["six.py"],
    srcs_version = "PY2AND3",
    visibility = ["//visibility:public"],
)
"""

GFLAGS_BUILD_FILE = """
py_library(
    name = "gflags",
    srcs =  glob(["gflags/**/*.py"]),
    visibility = ["//visibility:public"],
)
"""

def skydoc_repositories():
  """Adds the external repositories used by the skylark rules."""
  native.http_archive(
      name = "protobuf",
      url = "https://github.com/google/protobuf/archive/v3.4.1.tar.gz",
      sha256 = "8e0236242106e680b4f9f576cc44b8cd711e948b20a9fc07769b0a20ceab9cc4",
      strip_prefix = "protobuf-3.4.1",
  )

  # Protobuf expects an //external:python_headers label which would contain the
  # Python headers if fast Python protos is enabled. Since we are not using fast
  # Python protos, bind python_headers to a dummy target.
  native.bind(
      name = "python_headers",
      actual = "//:dummy",
  )

  native.new_http_archive(
      name = "markupsafe_archive",
      url = "https://pypi.python.org/packages/4d/de/32d741db316d8fdb7680822dd37001ef7a448255de9699ab4bfcbdf4172b/MarkupSafe-1.0.tar.gz#md5=2fcedc9284d50e577b5192e8e3578355",
      sha256 = "a6be69091dac236ea9c6bc7d012beab42010fa914c459791d627dad4910eb665",
      build_file_content = MARKUPSAFE_BUILD_FILE,
      strip_prefix = "MarkupSafe-1.0",
  )

  native.bind(
      name = "markupsafe",
      actual = "@markupsafe_archive//:markupsafe",
  )

  native.new_http_archive(
      name = "jinja2_archive",
      url = "https://pypi.python.org/packages/90/61/f820ff0076a2599dd39406dcb858ecb239438c02ce706c8e91131ab9c7f1/Jinja2-2.9.6.tar.gz#md5=6411537324b4dba0956aaa8109f3c77b",
      sha256 = "ddaa01a212cd6d641401cb01b605f4a4d9f37bfc93043d7f760ec70fb99ff9ff",
      build_file_content = JINJA2_BUILD_FILE,
      strip_prefix = "Jinja2-2.9.6",
  )

  native.bind(
      name = "jinja2",
      actual = "@jinja2_archive//:jinja2",
  )

  native.new_http_archive(
      name = "mistune_archive",
      url = "https://pypi.python.org/packages/25/a4/12a584c0c59c9fed529f8b3c47ca8217c0cf8bcc5e1089d3256410cfbdbc/mistune-0.7.4.tar.gz#md5=92d01cb717e9e74429e9bde9d29ac43b",
      sha256 = "8517af9f5cd1857bb83f9a23da75aa516d7538c32a2c5d5c56f3789a9e4cd22f",
      build_file_content = MISTUNE_BUILD_FILE,
      strip_prefix = "mistune-0.7.4",
  )

  native.bind(
      name = "mistune",
      actual = "@mistune_archive//:mistune",
  )

  native.new_http_archive(
      name = "six_archive",
      url = "https://pypi.python.org/packages/16/d8/bc6316cf98419719bd59c91742194c111b6f2e85abac88e496adefaf7afe/six-1.11.0.tar.gz#md5=d12789f9baf7e9fb2524c0c64f1773f8",
      sha256 = "70e8a77beed4562e7f14fe23a786b54f6296e34344c23bc42f07b15018ff98e9",
      build_file_content = SIX_BUILD_FILE,
      strip_prefix = "six-1.11.0",
  )

  native.bind(
      name = "six",
      actual = "@six_archive//:six",
  )

  native.new_http_archive(
      name = "gflags_repo",
      url = "https://github.com/google/python-gflags/archive/3.1.1.tar.gz",
      sha256 = "5ff27fa08c613706a9f488635bf38618c1587995ee3e9818b1562b19f4f498de",
      strip_prefix = "python-gflags-3.1.1",
      build_file_content = GFLAGS_BUILD_FILE,
  )

  native.bind(
      name = "gflags",
      actual = "@gflags_repo//:gflags",
  )
