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

- [v] server

- [v] http rack control cycle

- [v] Rack hijack (full/partial)
- [v] More Rack tests. Where can they come from?
  - [ ] Roda apps

- [ ] application loading / bootstrapping
  - [ ] load .ru files
  - [ ] process warmup

- [ ] benchmarks
  - [ ] compare to falcon, puma
  - [ ] using a Roda app with a few different endpoints representing different
    types of requests:
    - [ ] GET rendered template, simulate DB select query
    - [ ] POST params, simulate DB update query, response redirects to another URL
    - [ ] POST params, simulate DB update query, JSON response
  - [ ] different concurrency levels: 10 50 100 500 1000 5000
