# frozen_string_literal: true

require_relative 'helper'
require 'uma/server'

class ServerControlTest < UMBaseTest
  ServerControl = Uma::ServerControl

  def setup
    super
    @env = { foo: 42 }
  end

  def test_server_config
    config = Uma::ServerControl.server_config({})
    assert_equal 2, config[:thread_count]
  end

  def test_await_termination_term
    r, w = UM.pipe
    pid = fork do
      m = UM.new
      m.close(r)
      m.spin { sleep(0.05); m.write(w, 'ready') }
      ServerControl.await_termination(m)
      m.write(w, 'done')
      m.close(w)
    end
    machine.close(w)
    buf = +''

    machine.read(r, buf, 128)
    assert_equal 'ready', buf

    Process.kill('SIGTERM', pid)
    machine.read(r, buf, 128)
    assert_equal 'done', buf
  ensure
    machine.close(r) rescue nil
    machine.close(w) rescue nil
    if pid
      Process.kill('SIGKILL', pid)
      Process.wait(pid)
    end
  end

  def test_await_termination_int
    r, w = UM.pipe
    pid = fork do
      m = UM.new
      m.close(r)
      m.spin { sleep(0.05); m.write(w, 'ready') }
      ServerControl.await_termination(m)
      m.write(w, 'done')
      m.close(w)
    end
    machine.close(w)
    buf = +''

    machine.read(r, buf, 128)
    assert_equal 'ready', buf

    Process.kill('SIGINT', pid)
    machine.read(r, buf, 128)
    assert_equal 'done', buf
  ensure
    machine.close(r) rescue nil
    machine.close(w) rescue nil
    if pid
      Process.kill('SIGKILL', pid)
      Process.wait(pid)
    end
  end

  def test_worker_thread_graceful_stop
    buf = []

    accept_fibers = 3.times.map { |i|
      machine.spin do
        machine.sleep(0.05)
        buf << "accept_#{i}_done"
      rescue UM::Terminate
        buf << "accept_#{i}_terminated"
      end
    }

    connection_fibers = 3.times.map { |i|
      machine.spin do
        machine.sleep(0.05)
        buf << "connection_#{i}_done"
      rescue UM::Terminate
        buf << "connection_#{i}_terminated"
      end
    }

    ServerControl.worker_thread_graceful_stop(machine, accept_fibers, connection_fibers)

    assert_equal %w{
      accept_0_terminated accept_1_terminated accept_2_terminated
      connection_0_done connection_1_done connection_2_done
    }, buf.sort
  end

  def test_start_connection
    s1, s2 = UM.socketpair(UM::AF_UNIX, UM::SOCK_STREAM, 0)
    config = {}
    ff = Set.new
    
    f = ServerControl.start_connection(machine, config, ff, s2)
    assert_kind_of Fiber, f
    assert_equal 0, ff.size

    machine.snooze
    assert_equal 1, ff.size
    assert_equal [f], ff.to_a
    
    machine.write(s1, 'foobar')
    buf = +''
    machine.read(s1, buf, 128)
    assert_equal 'foobar', buf
    3.times { machine.snooze }
    assert_equal 0, ff.size
  ensure
    machine.close(s1)
    machine.close(s2) rescue nil
  end

  def assign_port
    @@port_assign_mutex ||= Mutex.new
    @@port_assign_mutex.synchronize do
      @@port ||= 10001 + SecureRandom.rand(50000)
      @@port += 1
    end
  end

  def test_prepare_listening_socket
    port = assign_port
    listen_fd = ServerControl.prepare_listening_socket(machine, '127.0.0.1', port)
    assert_kind_of Integer, listen_fd

    f = machine.spin {
      sock = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
      res = machine.connect(sock, '127.0.0.1', port)
      machine.close(sock)
      res
    }

    fd = machine.accept(listen_fd)
    assert_equal 0, machine.join(f)
    assert_kind_of Integer, fd
    machine.close(fd)
  end

  def test_start_acceptors
    port = assign_port
    config = {
      bind_entries: [
        ['127.0.0.1', port]
      ]
    }
    connection_fibers = []

    accept_fibers = ServerControl.start_acceptors(machine, config, connection_fibers)

    assert_kind_of Set, accept_fibers
    assert_equal 1, accept_fibers.size
    assert_kind_of Fiber, accept_fibers.to_a.first

    10.times { machine.snooze }

    sock = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock, '127.0.0.1', port)
    assert_equal 0, res

    3.times { machine.snooze }

    assert_equal 1, connection_fibers.size
    assert_kind_of Fiber, connection_fibers.first
  ensure
    accept_fibers.each { machine.schedule(it, UM::Terminate.new) }
    machine.await_fibers(accept_fibers)

    connection_fibers.each { machine.schedule(it, UM::Terminate.new) }
    machine.await_fibers(connection_fibers)
  end

  def start_test_worker_thread
    config = {}

    stop_queue = UM::Queue.new
    th = ServerControl.start_worker_thread(config, stop_queue)

    machine.sleep(0.05)
    
  end
end
