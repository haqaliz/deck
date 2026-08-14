# Inline brief: shared-parser-tests

Source: deck-next handoff (2026-08-15).

Add the M4 tests milestone: a real XCTest target for the Shared parsers
(ROADMAP.md:53) — GitLogParser, OpenBox ModelParser/session cost rows,
formatters, and the opencode DB SQL — since every feature so far deleted its
scratch SwiftPM package at merge and the repo now has zero tests and no
testTarget in native/project.yml. Port the test cases from git history where
possible, otherwise re-derive from parser behavior; keep tests at the
pure-parser layer per the CLAUDE.md convention. Note the caveat: this touches
project.yml (xcodegen) once for the test target — nothing else in the widget
shell changes, and future widgets should keep their scratch-package TDD pattern
until this lands.
