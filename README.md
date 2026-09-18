# bash-scripts 

[![Build Status](https://travis-ci.org/robertdebock/bash-scripts.svg?branch=master)](https://travis-ci.org/robertdebock/bash-scripts)

Sample scripts in bash. Mostly for my own reference, but feel free to use or clone.

## Versions

Every script that runs unattended somewhere carries a `VERSION="x.y"` line near the top,
with a one-line history above it. **Bump it on every change**: raise the second number for
a fix or a small change, the first for a change in behaviour or options that callers
depend on. The machines that run these scripts compare the installed `VERSION` with the
one in this repository; a lower number means an update is waiting, and the same number
with different content means the copy on the machine was edited without a new number.
