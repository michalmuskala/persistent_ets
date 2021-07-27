# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.1 (14.08.2019)

### Bug fixes

* Fix `PersistentEts.new/3` (broken since `0.2.0`).

## 0.2.0 (02.08.2019)

### Changes

* Use `DynamicSupervisor` instead of `:simple_one_for_one` and migrate to the
  Elixir 1.5 child specs.
* Improve documentation.

## 0.1.0 (02.03.2017)

* Initial release
