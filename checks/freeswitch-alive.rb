#! /usr/bin/env ruby
# encoding: UTF-8
# <script name>
#
# DESCRIPTION:
# This plugin uses vmstat to collect basic system metrics, produces
# Graphite formated output.
#
# OUTPUT:
# metric data
#
# PLATFORMS:
# Linux
#
# DEPENDENCIES:
# gem: sensu-plugin
# gem: socket
#
# USAGE:
#
# NOTES:
#
# LICENSE:
# Copyright 2011 Sonian, Inc <chefs@sonian.net>
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'socket'
require 'ESL'

class CheckFreeSWITCH < Sensu::Plugin::Check::CLI
  option :pid_file,
         description: 'FreeSWITCH pid file',
         short: '-p PID-FILE',
         long: '--pidfile PID-FILE',
         default: '/usr/local/freeswitch/run/freeswitch.pid'

  def get_metrics
    con = ESL::ESLconnection.new('127.0.0.1', '8021', 'ClueCon')
    esl = con.sendRecv('api show calls count')
    calls = esl.getBody.to_i

    esl = con.sendRecv('api show channels count')
    channels = esl.getBody.to_i

    result = { :calls => calls, :channels => channels }
  end

  def run
    if File.exist?(config[:pid_file])
      con = ESL::ESLconnection.new('127.0.0.1', '8021', 'ClueCon')
      esl = con.sendRecv('api status')
      status = esl.getBody.match(/FreeSWITCH.*/)
      ok "#{status}"
    else
      critical "Error message: FreeSWITCH is not running" 
    end
  end
end
