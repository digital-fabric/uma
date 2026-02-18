# frozen_string_literal: true

require 'uringmachine/fiber_scheduler'

module Uma

  class Server
    def initialize(env)
      @env = env
    end

    def start
      machine = UM.new
      stop_queue = UM::Queue.new

      config = ServerControl.server_config(@env)
      threads = config[:thread_count].times.map {
        ServerControl.start_worker_thread(config, stop_queue)
      }
      
      ServerControl.await_termination(machine)

      config[:thread_count].times { machine.push(stop_queue, :stop) }
      threads.each(&:join)
    end
  end

  module ServerControl
    extend self

    def server_config(env)
      {
        thread_count: 2
      }
    end

    def start_worker_thread(config, stop_queue)
      Thread.new do
        machine = UM.new
        scheduler = UM::FiberScheduler.new(machine)
        Fiber.set_scheduler(scheduler)

        worker_thread(machine, config, stop_queue)
      end
    end

    def worker_thread(machine, config, stop_queue)
      connection_fibers = Set.new
      accept_fibers = start_acceptors(machine, config, connection_fibers)

      machine.shift(stop_queue)
        
      worker_thread_graceful_stop(machine, accept_fibers, connection_fibers)
    end

    # @return [Set<Fiber>] a set of accept fibers
    def start_acceptors(machine, config, connection_fibers)
      set = Set.new
      return set if !config[:bind_entries] || config[:bind_entries].empty?

      config[:bind_entries].each do
        host, port = it
        set << machine.spin {
          fd = prepare_listening_socket(machine, host, port)
          machine.accept_each(fd) {
            start_connection(machine, config, connection_fibers, it)
          }
        }
      end
      set
    end

    def prepare_listening_socket(machine, host, port)
      fd = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
      machine.setsockopt(fd, UM::SOL_SOCKET, UM::SO_REUSEPORT, true)
      machine.bind(fd, host, port)
      machine.listen(fd, UM::SOMAXCONN)
      fd
    end

    # @return [Fiber]
    def start_connection(machine, config, connection_fibers, fd)
      f = machine.spin do
        connection_fibers << f
        buf = +''
        machine.read(fd, buf, 128)
        machine.write(fd, buf)
        machine.close(fd)
      ensure
        connection_fibers.delete(f)
      end
    end

    def worker_thread_graceful_stop(machine, accept_fibers, connection_fibers)
      # stop accepting connections
      accept_fibers.each { machine.schedule(it, UM::Terminate.new) }
      machine.await_fibers(accept_fibers)

      # graceful stop with a timeout of 10 seconds
      machine.timeout(10, UM::Terminate) do
        machine.await_fibers(connection_fibers)
      rescue UM::Terminate
        alive = connection_fibers.reject(&:done?)
        alive.each { machine.schedule(it, UM::Terminate.new) }
        machine.await_fibers(alive)
      end
    end

    def await_termination(machine)
      sig_queue = UM::Queue.new
      trap('SIGTERM') {
        machine.push(sig_queue, :term)
        trap('SIGTERM') { exit! }
      }
      trap('SIGINT')  {
        machine.push(sig_queue, :int)
        trap('SIGTERM') { exit! }
      }

      machine.shift(sig_queue)
    end
  end
end
