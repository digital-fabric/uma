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

    port1 = random_port
    port2 = random_port

    port = random_port
    config = Uma::ServerControl.server_config({
      bind: ["127.0.0.1:#{port1}", "127.0.0.1:#{port2}"]
    })
    assert_equal 2, config[:thread_count]
    assert_equal [
      ['127.0.0.1', port1], ['127.0.0.1', port2]
    ], config[:bind_entries]


    config = Uma::ServerControl.server_config({
      bind: "127.0.0.1:#{port1}"
    })
    assert_equal 2, config[:thread_count]
    assert_equal [['127.0.0.1', port1]], config[:bind_entries]

    conn_proc = ->(machine, fd) { }
    config = Uma::ServerControl.server_config({
      connection_proc: conn_proc,
    })
    assert_equal conn_proc, config[:connection_proc]
  end

  def test_await_process_termination_term
    r, w = UM.pipe
    pid = fork do
      m = UM.new
      m.close(r)
      m.spin { sleep(0.05); m.write(w, 'ready') }
      ServerControl.await_process_termination(m)
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

  def test_await_process_termination_int
    r, w = UM.pipe
    pid = fork do
      m = UM.new
      m.close(r)
      m.spin { sleep(0.05); m.write(w, 'ready') }
      ServerControl.await_process_termination(m)
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
    config = {
      connection_proc: ->(machine, fd) {
        buf = +''
        machine.recv(fd, buf, 128, 0)
        machine.send(fd, buf, buf.bytesize, 0)
      }
    }
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

  def test_prepare_listening_socket
    port = random_port
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
    port1 = random_port
    port2 = random_port
    config = {
      bind_entries: [
        ['127.0.0.1', port1],
        ['127.0.0.1', port2]
      ]
    }
    connection_fibers = []
    accept_fibers = ServerControl.start_acceptors(machine, config, connection_fibers)

    assert_kind_of Set, accept_fibers
    assert_equal 2, accept_fibers.size
    assert_kind_of Fiber, accept_fibers.to_a.first

    machine.sleep(0.05)

    sock1 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock1, '127.0.0.1', port1)
    assert_equal 0, res
    machine.snooze
    assert_equal 1, connection_fibers.size

    sock2 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock2, '127.0.0.1', port2)
    assert_equal 0, res
    machine.snooze
    assert_equal 1, connection_fibers.size # first connection will have been closed already

    3.times { machine.snooze }

    assert_equal 0, connection_fibers.size
  ensure
    machine.close(sock1) rescue nil
    machine.close(sock2) rescue nil
    if !accept_fibers.empty?
      machine.sleep(0.05)
      accept_fibers.each { machine.schedule(it, UM::Terminate.new) }
      machine.await_fibers(accept_fibers)
    end

    if !connection_fibers.empty?
      connection_fibers.each { machine.schedule(it, UM::Terminate.new) }
      machine.await_fibers(connection_fibers)
    end
  end

  def test_start_worker_thread
    port1 = random_port
    port2 = random_port
    config = {
      bind_entries: [
        ['127.0.0.1', port1],
        ['127.0.0.1', port2]
      ]
    }

    stop_queue = UM::Queue.new
    th = ServerControl.start_worker_thread(config, stop_queue)

    machine.sleep(0.05)
    
    sock1 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock1, '127.0.0.1', port1)
    assert_equal 0, res

    sock2 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock2, '127.0.0.1', port2)
    assert_equal 0, res

    machine.close(sock1)
    machine.close(sock2)

    machine.push(stop_queue, :stop)

    th.join
    th = nil

    sock1 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    assert_raises(Errno::ECONNREFUSED) { machine.connect(sock1, '127.0.0.1', port1) }
  ensure
    machine.close(sock1) rescue nil
    machine.close(sock2) rescue nil
    th&.kill
  end

  def test_start_acceptors_with_connection_proc
    port1 = random_port
    config = {
      bind_entries: [
        ['127.0.0.1', port1]
      ],
      connection_proc: ->(machine, fd) {
        machine.send(fd, 'hi', 2, 0)
      } 
    }
    connection_fibers = []
    accept_fibers = ServerControl.start_acceptors(machine, config, connection_fibers)

    assert_kind_of Set, accept_fibers
    assert_equal 1, accept_fibers.size
    assert_kind_of Fiber, accept_fibers.to_a.first

    machine.sleep(0.05)

    sock1 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock1, '127.0.0.1', port1)
    assert_equal 0, res
    buf = +''
    machine.recv(sock1, buf, 128, 0)
    assert_equal 'hi', buf
  ensure
    machine.close(sock1) rescue nil
    if !accept_fibers.empty?
      machine.sleep(0.05)
      accept_fibers.each { machine.schedule(it, UM::Terminate.new) }
      machine.await_fibers(accept_fibers)
    end

    if !connection_fibers.empty?
      connection_fibers.each { machine.schedule(it, UM::Terminate.new) }
      machine.await_fibers(connection_fibers)
    end
  end

  def test_start_acceptors_with_connection_proc_with_stream
    port1 = random_port
    config = {
      bind_entries: [
        ['127.0.0.1', port1]
      ],
      connection_proc: ->(machine, fd) {
        stream = UM::Stream.new(machine, fd)
        msg = stream.get_line(nil, 0)
        machine.send(fd, msg, msg.bytesize, 0)
      }
    }
    connection_fibers = []
    accept_fibers = ServerControl.start_acceptors(machine, config, connection_fibers)

    assert_kind_of Set, accept_fibers
    assert_equal 1, accept_fibers.size
    assert_kind_of Fiber, accept_fibers.to_a.first

    machine.sleep(0.05)

    sock1 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock1, '127.0.0.1', port1)
    assert_equal 0, res
    machine.send(sock1, "bar\n", 4, 0)
    buf = +''
    machine.recv(sock1, buf, 128, 0)
    assert_equal 'bar', buf
  ensure
    machine.close(sock1) rescue nil
    if !accept_fibers.empty?
      machine.sleep(0.05)
      accept_fibers.each { machine.schedule(it, UM::Terminate.new) }
      machine.await_fibers(accept_fibers)
    end

    if !connection_fibers.empty?
      connection_fibers.each { machine.schedule(it, UM::Terminate.new) }
      machine.await_fibers(connection_fibers)
    end
  end
end
