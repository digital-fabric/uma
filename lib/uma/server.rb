# frozen_string_literal: true

require 'uringmachine/fiber_scheduler'

module Uma

  class Server
    def initialize(env)
      @env = env
    end

    def start
      @machine = UM.new
      @stop_queue = UM::Queue.new

      @config = ServerControl.server_config(@env)
      @threads = @config[:thread_count].times.map {
        ServerControl.start_worker_thread(@config, @stop_queue)
      }
      
      ServerControl.await_process_termination(@machine)

      stop
    end

    def stop
      return if !@threads

      @config[:thread_count].times { @machine.push(@stop_queue, :stop) }
      @threads.each(&:join)
      @threads = nil
    end
  end

  module ServerControl
    extend self

    def server_config(env)
      {
        thread_count: 2,
        bind_entries: env[:bind] ? bind_entries(env[:bind]) : [],
        connection_proc: env[:connection_proc],
        error_stream: env[:error_stream]
      }
    end

    def bind_entries(bind_value)
      case bind_value
      when Array
        bind_value.map { parse_bind_spec(it) }
      when String
        [parse_bind_spec(bind_value)]
      else
        raise ArgumentError, "invalid bind value"
      end
    end

    BIND_SPEC_RE = /^(.+)\:(\d+)$/.freeze

    def parse_bind_spec(spec)
      if (m = spec.match(BIND_SPEC_RE))
        [m[1], m[2].to_i]
      else
        raise ArgumentError, "Invalid bind spec"
      end
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
        set << machine.spin do
          fd = prepare_listening_socket(machine, host, port)
          machine.accept_each(fd) { |fd|
            start_connection(machine, config, connection_fibers, fd)
          }
        rescue UM::Terminate
        ensure
          machine.close(fd)
        end
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
        config[:connection_proc]&.(machine, fd)
      ensure
        machine.close(fd) rescue nil
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

    def await_process_termination(machine)
      sig_queue = UM::Queue.new
      
      old_term_handler = trap('SIGTERM') {
        machine.push(sig_queue, :term)
        trap('SIGTERM', old_term_handler)
      }
      old_int_handler = trap('SIGINT')  {
        machine.push(sig_queue, :int)
        trap('SIGINT', old_int_handler)
      }

      machine.shift(sig_queue)
    end
  end
end
