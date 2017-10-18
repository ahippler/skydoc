workspace(name = "io_bazel_skydoc")

http_archive(
    name = "io_bazel_rules_sass",
    url = "https://github.com/bazelbuild/rules_sass/archive/0.0.3.tar.gz",
    sha256 = "14536292b14b5d36d1d72ae68ee7384a51e304fa35a3c4e4db0f4590394f36ad",
    strip_prefix = "rules_sass-0.0.3",
)
load("@io_bazel_rules_sass//sass:sass.bzl", "sass_repositories")
sass_repositories()

load("//skylark:skylark.bzl", "skydoc_repositories")
skydoc_repositories()
