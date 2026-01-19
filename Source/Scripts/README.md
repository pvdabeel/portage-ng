This directory contains various strategies for building, caching, graphing and syncing on different operating systems.

For running the main application from a clean environment (e.g. CI), prefer the
project-root `./Source/Scripts/portage-ng-dev` launcher, which mirrors the standard `swipl ... -g main -- ...`
invocation without relying on a shell alias.
