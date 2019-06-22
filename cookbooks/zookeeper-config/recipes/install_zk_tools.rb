# frozen_string_literal: true

# Cookbook:: zookeeper-config
# Recipe:: install_zk_tools
#
# Copyright:: 2019, Ali Jafari - Excella Data Lab, All Rights Reserved.

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
  'confluent-platform-oss-2.11'
].each do |pkg|
  package pkg
end

# python_runtime '2'
python_runtime '2' do
  # Workaround for https://github.com/poise/poise-python/issues/133
  get_pip_url 'https://github.com/pypa/get-pip/raw/f88ab195ecdf2f0001ed21443e247fb32265cabb/get-pip.py'
  pip_version '18.0'
end

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
# rubocop:enable Naming/HeredocDelimiterNaming

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

%w[aws-sdk trollop keystore].each do |gem|
  gem_package gem do
    timeout 3600
    options '--no-user-install'
  end
end

# bash 'install gems' do
#   code <<-EOH
#     gem install aws-sdk keystore
#   EOH
# end

# # for user root
# bash 'install gem as root' do
#   user 'root'
#   code <<-EOH
#     gem install aws-sdk trollop
#   EOH
# end

# bash 'install gems' do
#   code <<-EOH
#     source /usr/share/rvm/scripts/rvm
#     rvm --default use 2.5.3
#     gem install aws-sdk keystore trollop
#   EOH
#   user 'root'
#   group 'root'
# end