#
# Cookbook Name:: rabbitmq
# Recipe:: default
#
# Copyright 2009, Benjamin Black
# Copyright 2009-2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# rabbitmq-server is not well-behaved as far as managed services goes
# we'll need to add a LWRP for calling rabbitmqctl stop
# while still using /etc/init.d/rabbitmq-server start
# because of this we just put the rabbitmq-env.conf in place and let it rip

include_recipe "erlang"

directory "/etc/rabbitmq/" do
  owner "root"
  group "root"
  mode 0755
  action :create
end

template "/etc/rabbitmq/rabbitmq-env.conf" do
  source "rabbitmq-env.conf.erb"
  owner "root"
  group "root"
  mode 0644
  notifies :restart, "service[rabbitmq-server]"
end

case node[:platform]
when "debian", "ubuntu"
  # use the RabbitMQ repository instead of Ubuntu or Debian's
  # because there are very useful features in the newer versions
  apt_repository "rabbitmq" do
    uri "http://www.rabbitmq.com/debian/"
    distribution "testing"
    components ["main"]
    key "http://www.rabbitmq.com/rabbitmq-signing-key-public.asc"
    action :add
  end
  package "rabbitmq-server"
when "redhat", "centos", "scientific", "amazon"
  remote_file "/tmp/rabbitmq-server-#{node[:rabbitmq][:version]}-1.noarch.rpm" do
    source "https://www.rabbitmq.com/releases/rabbitmq-server/v#{node[:rabbitmq][:version]}/rabbitmq-server-#{node[:rabbitmq][:version]}-1.noarch.rpm"
    action :create_if_missing
  end
  remote_file "/tmp/rabbitmq-signing-key-public.asc" do
  source "http://www.rabbitmq.com/rabbitmq-signing-key-public.asc"
  action :create_if_missing
  end
  bash "installrabbitkey.sh" do
    command "rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc"
  end

  service "qpidd" do
    action [:disable, :stop]
  end
  rpm_package "/tmp/rabbitmq-server-#{node[:rabbitmq][:version]}-1.noarch.rpm" do
    action :install
  end

  execute "install rabbit management.sh" do
    command "/usr/sbin/rabbitmq-plugins enable rabbitmq_management"
  end
end

directory "/var/run/rabbitmq/" do
  owner "rabbitmq"
  group "rabbitmq"
  mode 0755
  action :create
end

cookbook_file '/etc/init.d/rabbitmq-server' do
  owner 'root'
  group 'root'
  mode   0755
  source 'rabbitmq-server'
  action :create
end

if node[:rabbitmq][:cluster]
    # If this already exists, don't do anything
    # Changing the cookie will stil have to be a manual process
    template "/var/lib/rabbitmq/.erlang.cookie" do
      source "doterlang.cookie.erb"
      owner "rabbitmq"
      group "rabbitmq"
      mode 0400
      not_if { File.exists? "/var/lib/rabbitmq/.erlang.cookie" }
    end
end

execute "change permissions on enabled_plugins" do
  command "chmod 644 /etc/rabbitmq/enabled_plugins"
end

template "/etc/rabbitmq/rabbitmq.config" do
  source "rabbitmq.config.erb"
  owner "root"
  group "root"
  mode 0644
  notifies :restart, "service[rabbitmq-server]", :immediately
end

service "rabbitmq-server" do
  stop_command "/usr/sbin/rabbitmqctl stop"
  start_command "service rabbitmq-server start"
  supports :status => true, :restart => true
  action [ :enable, :restart ]
end

execute "create user.sh" do
  command "rabbitmqctl add_user #{node[:rabbitmq][:default_user]} #{node[:rabbitmq][:default_pass]}"
  returns [0,2] # 0 = new user created, 2 = user already exists
end
execute "give user admin access.sh" do
  command "rabbitmqctl set_user_tags #{node[:rabbitmq][:default_user]} administrator"
end
execute "setup rabbit management commandline interface.sh" do
  command "wget --http-user=#{node[:rabbitmq][:default_user]} --http-password=#{node[:rabbitmq][:default_pass]} -O /usr/sbin/rabbitmqadmin http://localhost:55672/cli/rabbitmqadmin"
end
execute "change permissions on rabbit management commandline interface.sh" do
  command "chmod 755 /usr/sbin/rabbitmqadmin"
end
execute "remove default guest account.sh" do
  command "rabbitmqctl delete_user guest"
  returns [0,2] # 0 = user deleted, 2 = user already deleted
end
