# Chronim

**Chrome DevTools Protocol (CDP) client library for Nim**

Chronim is a high-level, idiomatic Nim library for communicating with Chrome (and other Chromium-based browsers) using the Chrome DevTools Protocol (CDP). It empowers Nim developers to automate browser tasks, instrument web pages, and gather performance data—all from Nim code.

## Features

- **Idiomatic Nim API for Chrome DevTools Protocol**, inspired by the simplicity and flexibility of [chrome-remote-interface](https://github.com/cyrus-and/chrome-remote-interface)
- **Full support for sending and receiving any CDP command**
- **Event-driven architecture** for handling all Chrome protocol events
- **\* Human-like automation behaviors in mind:**
  Designed with techniques and strategies that enable developers to mimic realistic user interactions, Chronim helps bypass bot detection used by modern front-end frameworks. This empowers robust browser automation—even on pages protected by sophisticated anti-bot measures.
- **\* Seamless Nim-to-WebAssembly (WASM) workflow:**
  Chronim lets you easily convert Nim code into WebAssembly modules, enabling you to embed and execute compiled Nim directly inside Chrome’s JS engine. This makes it possible to use Nim for complex browser-side tasks, including solving CAPTCHAs, processing data, or interacting with web pages at high performance.

## Motivation

Browser automation and inspection are essential for modern development and testing. While Nim offers both performance and expressiveness, there has been no ergonomic solution for browser control in Nim. Chronim aims to fill this gap as a full-featured CDP client, inspired by the proven interface style of chrome-remote-interface.

## Installation

Chronim can be installed using Nimble:

```sh
nimble install chronim
```
