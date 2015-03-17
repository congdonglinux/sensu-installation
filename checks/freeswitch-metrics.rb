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
require 'sensu-plugin/metric/cli'
require 'socket'
require 'ESL'

class FreeSWITCHStat < Sensu::Plugin::Metric::CLI::Graphite
  option :scheme,
         description: 'Metric naming scheme, text to prepend to .$parent.$child',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.freeswitch"

  def get_metrics
    con = ESL::ESLconnection.new('127.0.0.1', '8021', 'ClueCon')
    esl = con.sendRecv('api show calls count')
    calls = esl.getBody.to_i

    esl = con.sendRecv('api show channels count')
    channels = esl.getBody.to_i

    result = { :calls => calls, :channels => channels }
  end

  def run
    metrics = get_metrics
    timestamp = Time.now.to_i
    
    metrics.each do |child, value|
      output [config[:scheme], child].join('.'), value, timestamp
    end
    
    ok
  end
end
