# frozen_string_literal: true

# Cookbook:: zookeeper-config
# Recipe:: default
#
# Copyright:: 2018, Ali Jafari - Excella Data Lab, All Rights Reserved.

include_recipe 'zookeeper-config::service'
include_recipe 'lvm::default'

script 'download confluent key' do
  interpreter 'bash'
  code 'wget -qO - http://packages.confluent.io/deb/4.1/archive.key ' \
       '| apt-key add -'
end

script 'add confluent apt repo' do
  interpreter 'bash'
  code 'add-apt-repository "deb [arch=amd64] ' \
       'http://packages.confluent.io/deb/4.1 stable main"'
end

script 'apt-get update' do
  interpreter 'bash'
  code 'apt-get update'
end

[
  'awscli',
  'software-properties-common',
  'ruby',
  'confluent-platform-oss-2.11'
].each do |pkg|
  package pkg
end

# rubocop:disable Naming/HeredocDelimiterNaming

python_runtime '2'

%w[kazoo dnspython boto].each do |package|
  python_package package
end

python_package 'awscli' do
  version '1.14.50'
end

bash 'link correct aws version' do
  code <<-EOH
  rm -rf /usr/bin/aws
  chmod +x /usr/local/bin/aws
  ln -s /usr/local/bin/aws /usr/bin/aws
  EOH
end

bash 'install-cfn-tools' do
  code <<-SCRIPT
  apt-get update
  apt-get -y install python-setuptools
  mkdir aws-cfn-bootstrap-latest
  curl https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz | tar xz -C aws-cfn-bootstrap-latest --strip-components 1
  easy_install aws-cfn-bootstrap-latest
  SCRIPT
end

bash 'install gems' do
  code <<-EOH
  source /usr/local/rvm/scripts/rvm
  gem install aws-sdk keystore
  EOH
end
# rubocop:enable Naming/HeredocDelimiterNaming

# Prepare chef-solo work area for on-boot
directory '/var/chef/solo' do
  recursive true
  owner 'root'
  group 'root'
  mode '0755'
end

[
  'eni_switcher.rb',
  'network_config.sh.erb',
  'zk_server.rb',
  'zk_run.sh',
  'zookeeper.properties.erb',
  'myid.erb',
  'attach_ebs.py'
].each do |file|
  cookbook_file "/usr/local/bin/#{file}" do
    source file
    owner 'root'
    group 'root'
    mode '0755'
  end
end

# setup keystore env
vars = StringIO.new
vars << "export inventory_store=Pipeline_Key_Store\n"
vars << "export kms_id=fc112e37-27c7-4e56-b6e7-6744e226d07e\n"
vars << "export AWS_DEFAULT_REGION=us-east-1\n"

file '/etc/profile.d/keystore.sh' do
  content vars.string
  owner 'root'
  group 'root'
  mode '0755'
end

# prometheus setup
# cookbook_file '/opt/prometheus.yml' do
#   source 'prometheus.yml'
#   owner 'root'
#   group 'root'
#   mode '0755'
# end

# prometheus_agent = 'https://repo1.maven.org/maven2/io/prometheus/jmx/' \
#                    'jmx_prometheus_javaagent/0.6/' \
#                    'jmx_prometheus_javaagent-0.6.jar'
# remote_file '/opt/jmx_prometheus_javaagent-0.6.jar' do
#   source prometheus_agent
# end

# bash 'Download prometheus jar script' do
#   code <<-SCRIPT
#     /usr/bin/aws s3api get-object --bucket ex-data-lab-binaries \
#       --key jmx_prometheus_javaagent-0.6.jar /opt/jmx_prometheus_javaagent-0.6.jar
#     SCRIPT
#   not_if { ::File.exist?('/opt/jmx_prometheus_javaagent-0.6.jar') }
#   not_if { node['test_kitchen'] }
# end