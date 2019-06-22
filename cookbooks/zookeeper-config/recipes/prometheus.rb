# frozen_string_literal: true

# Cookbook:: zookeeper-config
# Recipe:: prometheus
#
# Copyright:: 2019, Ali Jafari - Excella Data Lab, All Rights Reserved.

cookbook_file '/opt/prometheus.yml' do
  source 'prometheus.yml'
  owner 'root'
  group 'root'
  mode '0755'
end

prometheus_agent = 'https://repo1.maven.org/maven2/io/prometheus/jmx/' \
                   'jmx_prometheus_javaagent/0.6/' \
                   'jmx_prometheus_javaagent-0.6.jar'
remote_file '/opt/jmx_prometheus_javaagent-0.6.jar' do
  source prometheus_agent
end

# bash 'Download prometheus jar script' do
#   code <<-SCRIPT
#     /usr/bin/aws s3api get-object --bucket xsp-binaries \
#       --key jmx_prometheus_javaagent-0.6.jar /opt/jmx_prometheus_javaagent-0.6.jar
#     SCRIPT
#   not_if { ::File.exist?('/opt/jmx_prometheus_javaagent-0.6.jar') }
#   not_if { node['test_kitchen'] }
# end
