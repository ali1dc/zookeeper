Zookeeper is an orchestration service, typically associated with distributed systems (think Hadoop or Kafka). Managing Zookeeper, especially in cloud environments, can be difficult. In this blog post, I will address the challenge of deploying Zookeeper as a Service on Amazon Web Services (AWS); but first, let's see what Zookeeper is, and why we need it!

## What is Zookeeper
Zookeeper is a centralized service. It maintains configuration information and naming, and it provides distributed synchronization and group services. All of these are a requirement for distributed applications. Distributed applications are difficult to implement; they introduce the possibility of bugs and race conditions. Implementing services to manage them is challenging and application designers often skimp on them, leading to brittle architectures that are difficult to manage. Even when done correctly, different approaches to implementation can lead to unnecessary complexity.

Zookeeper can help address these challenges by providing a very simple interface to a centralized coordination service. The service itself is distributed and highly reliable. Consensus, group management, and presence protocols are implemented by Zookeeper so that the applications do not need to implement them on their own. However, some work is needed to integrate applications with Zookeeper effectively. I'll describe how to use it with Kafka.

## Why we need it
#### Controller Election
The controller is one of the most important broking entities in a Kafka ecosystem. It maintains the leader-follower relationship across all the partitions. If a node is shutting down, the controller must tell all the replicas to act as partition leaders so that the duties of the partition leaders on the node that is about to fail are fulfilled. This means that whenever a node shuts down, a new controller can be elected. It also means that, at any given time, there is only one controller and all the follower nodes agree on its identity.
#### Topics Configuration
This configuration stores all the topics and their current state, including the list of existing topics, the number of partitions for each topic, the location of all the replicas, the list of configuration overrides, and which node is the preferred leader.
#### ACLs
Zookeeper will maintain access control lists (ACLs) for all the topics.
#### Cluster Membership
Zookeeper will maintain a list of all the brokers that are functioning at any given moment within the cluster.
#### Quotas
How much data each client is allowed to read and write.

**Please note** that Zookeeper in a mandatory service for running Apache Kafka.

## Challenge with cloud
Zookeeper can be provisioned on AWS with a single command. However, taking full advantage of its capabilities requires much more work. In a Zookeeper cluster there are number of machines or servers; each one is called a node. Each node needs to know the network information (IP or hostname) of the other nodes and the other services Zookeeper is managing (like Kafka) need to know Zookeeper's network information.

If we have a Zookeeper cluster on AWS, we'll likely deploy it on EC2 instances with an Auto Scaling Group - ASG. In that dynamic environment, what happens if a node got replaced by another one? How do other nodes and other services learn the new node's information?

There are several options for addressing that challenge:
1. Using [Consul](https://www.consul.io/discovery.html) service discovery by HashiCorp.
2. Create a custom node discovery routine, which will be complicated and challenging.
3. Using [Exhibitor](https://github.com/soabase/exhibitor); a Zookeeper node management by Netflix.
4. Use stateless Zookeeper, also known as Zookeeper as a Service.

I will focus the last of these, Zookeeper as a Service, or Stateless Zookeeper.

## What is stateless Zookeeper
Stateless Zookeeper is a Zookeeper cluster, configured so that if a node is terminated, the replacement node will get the same node configuration and no data will be lost.

In this section, I will describe step-by-step how to deploy a stateless Zookeeper cluster in AWS. First, I will establish some assumptions:
1. We are hosting 3 Zookeeper nodes on `us-east-1` and each node is hosted on one Available Zone (AZ): `us-east-1a`, `us-east-1b` and `us-east-1c`.
2. We are installing Zookeeper on EC2 instances. Each node on one EC2 instance.
3. We are using ASG.
4. We have an Amazon Machine Image (AMI) with Zookeeper on it. We are using [Chef](https://www.chef.io/) to bake Zookeeper and all the tools needed to run it.

### Step 1: Leveraging ENI
We need to create an environment with static internal IP addresses for the nodes, so that if a node is replaced, the new one will get the same IP address. With Elastic Network Interface (ENI), we can manage this in a straightforward manner.

In our ASG launch configuration, we need to include a script to look for an available ENI in the same AZ and attach it. Here is a ruby example:
```ruby
@ec2 = Aws::EC2::Client.new(region: region)
metadata_endpoint = 'http://169.254.169.254/latest/meta-data/'
instance_az = Net::HTTP.get(URI.parse(metadata_endpoint + 'placement/availability-zone'))
# get the available eni
eni = @ec2.describe_network_interfaces(
  filters: [
    { name: 'tag:Name', values: ['ZOOKEEPER-' + '*'] },
    { name: 'availability-zone', values: [instance_az] },
    { name: 'status', values: ['available'] }
  ]).network_interfaces[0]
```
Now we simply can attach the network:
```ruby
metadata_endpoint = 'http://169.254.169.254/latest/meta-data/'
instance_id = Net::HTTP.get(URI.parse(metadata_endpoint + 'instance-id'))
eni.attach(instance_id: instance_id, device_index: 1)
```
At this point, we have defined the static IP address and attached it to our EC2 instance, but we are not able to use it for communication yet! First, we must create a network config and route, and make our newly attached network device (the ENI) the default. This can be managed by a shell script:
```sh
#!/bin/bash -e
export GATEWAY=`route -n | grep "^0.0.0.0" | tr -s " " | cut -f2 -d" "`

if [ -f /etc/network/interfaces.d/eth1.cfg ]; then mv -f /etc/network/interfaces.d/eth1.cfg /etc/network/interfaces.d/backup.eth1.cfg.backup; fi
cat > /etc/network/interfaces.d/eth1.cfg <<ETHCFG
auto eth1
iface eth1 inet dhcp
    up ip route add default via $GATEWAY dev eth1 table eth1_rt
    up ip rule add from <%= new_ip_address %> lookup eth1_rt prio 1000
ETHCFG

mv /etc/iproute2/rt_tables /etc/iproute2/backup.rt_tables.backup
cat > /etc/iproute2/rt_tables <<RTTABLES
#
# reserved values
#
255     local
254     main
253     default
0       unspec
#
# local
#
#1      inr.ruhep
2 eth1_rt
RTTABLES

ifup eth1

ip route add default via $GATEWAY dev eth1 table eth1_rt;
```

These scripts can be run by Chef in the ASG launch configuration.

### Step 2: Leveraging EBS volume
Now that we have our nodes and ENIs configured, we need to consider data persistence. What happens if a node is terminated? How do we ensure no data is lost?

Good news: nothing is going to happen! Zookeeper is a fault-tolerant and distributed system; each node has the same data replicated.
Bad news: after each node replacement we will have traffic in our network to replicate data to the new node.
Solution: use an extra Elastic Block Storage (EBS) volume. Set the `Delete on termination` property to `false` and attach the volume to the newly replaced node. It will store the Zookeeper data. Here is a python script for this:
```python
from boto import ec2
import commands

conn = ec2.connect_to_region(region_name)

volume = conn.get_all_volumes(
  filters = {
    'tag:Name':tag,
    'availability-zone':instance_az,
    'status':'available'
  })[0]
# attach the volume
conn.attach_volume(volume.id, instance_id, '/dev/xvdg')
# mount it
commands.getstatusoutput('mount /dev/xvdg /var/lib/zookeeper')
```
## Conclusion
Configuring Stateless Zookeeper has its challenges, but it is easier than the other options mentioned above. In addition, because this custom code can be managed and deployed internally, we have more power to customize it for a specific organization. One great characteristic of Stateless Zookeeper is that it has Self-Healing Clusters! The examples above don't make use of that, but, with some minor improvements, we can use the same pattern to introduce it.

[Here](https://github.com/ali1dc/zookeeper) is where you can find the source code for the Zookeeper configuration, ready for AWS deployment.

### References
- https://zookeeper.apache.org/
- https://www.cloudkarafka.com/blog/2018-07-04-cloudkarafka_what_is_zookeeper.html
