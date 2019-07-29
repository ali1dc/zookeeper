# frozen_string_literal: true

# Cookbook:: zookeeper-config
# Recipe:: default
#
# Copyright:: 2018, Ali Jafari - Excella Data Lab, All Rights Reserved.

include_recipe 'zookeeper-config::service'
include_recipe 'lvm::default'
include_recipe 'zookeeper-config::rvm'
include_recipe 'zookeeper-config::install_zk_tools'
include_recipe 'zookeeper-config::keystore'
include_recipe 'zookeeper-config::prometheus'
