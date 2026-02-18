## Basic functionality

We work from the outside to the inside. Generally, we start from the script to
start the server, to the concurrency controls, to the actual HTTP server, to the
Rack interface.

- [v] bin script
  - [v] `uma serve`

- [v] concurrency model
  - M threads x N fibers
  - Clear lifecycle management - start, run, stop
  - Each thread sets up a UringMachine instance and a fiber scheduler
  - Graceful stop
