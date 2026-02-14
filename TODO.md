## Basic functionality

We work from the outside to the inside. Generally, we start from the script to
start the server, to the concurrency controls, to the actual HTTP server, to the
Rack interface.

- [ ] bin script
  - [ ] `uma serve`

- [ ] concurrency model
  - P processes x T threads x F fibers
  - reforking (following https://github.com/Shopify/pitchfork)
    see also: https://byroot.github.io/ruby/performance/2025/03/04/the-pitchfork-story.html
    - Monitor worker memory usage - how much is shared
    - Choose worker with most served request count as "mold" for next generation
    - Perform GC out of band, preferably when there are no active requests
      https://railsatscale.com/2024-10-23-next-generation-oob-gc/
    - When a worker is promoted to "mold", it:
      - Stops `accept`ing requests
      - When finally idle, calls `Process.warmup`
      - Starts replacing sibling workers with forked workers
    see also: https://www.youtube.com/watch?v=kAW5O2dkSU8 
  - on each worker process - 1 or more threads
    - Clear lifecycle management - start, run, stop, mold
    - Each thread sets up a UringMachine instance and a fiber scheduler
    - Graceful stop


